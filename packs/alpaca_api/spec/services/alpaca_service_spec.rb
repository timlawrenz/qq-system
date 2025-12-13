# frozen_string_literal: true

# rubocop:disable RSpec/ContextWording

require 'rails_helper'

RSpec.describe AlpacaService, type: :service do
  let(:mock_client) { instance_double(Alpaca::Trade::Api::Client) }

  before do
    allow(Alpaca::Trade::Api::Client).to receive(:new).and_return(mock_client)
    allow(Rails.logger).to receive(:info)
    allow(Rails.logger).to receive(:warn)
  end

  describe '#initialize' do
    context 'when TRADING_MODE not set' do
      it 'raises KeyError to prevent silent defaults' do
        ClimateControl.modify TRADING_MODE: nil, ALPACA_PAPER_API_KEY_ID: 'PK123',
                              ALPACA_PAPER_API_SECRET_KEY: 'secret' do
          expect { described_class.new }.to raise_error(KeyError, /TRADING_MODE/)
        end
      end
    end

    context 'paper mode' do
      it 'uses paper endpoint when TRADING_MODE=paper' do
        ClimateControl.modify TRADING_MODE: 'paper', ALPACA_PAPER_API_KEY_ID: 'PK123',
                              ALPACA_PAPER_API_SECRET_KEY: 'secret' do
          expect(Alpaca::Trade::Api::Client).to receive(:new).with(
            endpoint: 'https://paper-api.alpaca.markets',
            key_id: 'PK123',
            key_secret: 'secret'
          )
          described_class.new
        end
      end

      it 'uses paper credentials' do
        ClimateControl.modify TRADING_MODE: 'paper', ALPACA_PAPER_API_KEY_ID: 'PK456',
                              ALPACA_PAPER_API_SECRET_KEY: 'secret123' do
          expect(Alpaca::Trade::Api::Client).to receive(:new).with(
            endpoint: 'https://paper-api.alpaca.markets',
            key_id: 'PK456',
            key_secret: 'secret123'
          )
          described_class.new
        end
      end

      it 'logs paper mode activation' do
        ClimateControl.modify TRADING_MODE: 'paper', ALPACA_PAPER_API_KEY_ID: 'PK123',
                              ALPACA_PAPER_API_SECRET_KEY: 'secret' do
          expect(Rails.logger).to receive(:info).with('Trading mode: PAPER | Endpoint: https://paper-api.alpaca.markets')
          described_class.new
        end
      end
    end

    context 'live mode' do
      it 'raises error when TRADING_MODE=live without confirmation' do
        ClimateControl.modify TRADING_MODE: 'live', ALPACA_LIVE_API_KEY_ID: 'AK123',
                              ALPACA_LIVE_API_SECRET_KEY: 'secret', CONFIRM_LIVE_TRADING: nil do
          expect { described_class.new }.to raise_error(
            AlpacaService::SafetyError,
            'Live trading requires CONFIRM_LIVE_TRADING=yes environment variable'
          )
        end
      end

      it 'uses live endpoint when TRADING_MODE=live and confirmed' do
        ClimateControl.modify TRADING_MODE: 'live', ALPACA_LIVE_API_KEY_ID: 'AK123',
                              ALPACA_LIVE_API_SECRET_KEY: 'secret', CONFIRM_LIVE_TRADING: 'yes' do
          expect(Alpaca::Trade::Api::Client).to receive(:new).with(
            endpoint: 'https://api.alpaca.markets',
            key_id: 'AK123',
            key_secret: 'secret'
          )
          described_class.new
        end
      end

      it 'uses live credentials' do
        ClimateControl.modify TRADING_MODE: 'live', ALPACA_LIVE_API_KEY_ID: 'AK789',
                              ALPACA_LIVE_API_SECRET_KEY: 'livesecret', CONFIRM_LIVE_TRADING: 'yes' do
          expect(Alpaca::Trade::Api::Client).to receive(:new).with(
            endpoint: 'https://api.alpaca.markets',
            key_id: 'AK789',
            key_secret: 'livesecret'
          )
          described_class.new
        end
      end

      it 'logs prominent warning' do
        ClimateControl.modify TRADING_MODE: 'live', ALPACA_LIVE_API_KEY_ID: 'AK123',
                              ALPACA_LIVE_API_SECRET_KEY: 'secret', CONFIRM_LIVE_TRADING: 'yes' do
          expect(Rails.logger).to receive(:warn).with('🚨 LIVE TRADING MODE ACTIVE 🚨')
          expect(Rails.logger).to receive(:info).with('Trading mode: LIVE | Endpoint: https://api.alpaca.markets')
          described_class.new
        end
      end
    end

    context 'validation errors' do
      it 'raises ConfigurationError for invalid TRADING_MODE' do
        ClimateControl.modify TRADING_MODE: 'invalid', ALPACA_PAPER_API_KEY_ID: 'PK123',
                              ALPACA_PAPER_API_SECRET_KEY: 'secret' do
          expect { described_class.new }.to raise_error(
            AlpacaService::ConfigurationError,
            "Invalid TRADING_MODE: invalid. Must be 'paper' or 'live'"
          )
        end
      end

      it 'raises ConfigurationError for missing paper credentials' do
        ClimateControl.modify TRADING_MODE: 'paper', ALPACA_PAPER_API_KEY_ID: nil,
                              ALPACA_PAPER_API_SECRET_KEY: 'secret' do
          expect { described_class.new }.to raise_error(
            AlpacaService::ConfigurationError,
            'Missing ALPACA_PAPER_API_KEY_ID for paper trading mode'
          )
        end
      end

      it 'raises ConfigurationError for missing live credentials' do
        ClimateControl.modify TRADING_MODE: 'live', ALPACA_LIVE_API_KEY_ID: 'AK123', ALPACA_LIVE_API_SECRET_KEY: nil,
                              CONFIRM_LIVE_TRADING: 'yes' do
          expect { described_class.new }.to raise_error(
            AlpacaService::ConfigurationError,
            'Missing ALPACA_LIVE_API_SECRET_KEY for live trading mode'
          )
        end
      end

      it 'raises SafetyError for live mode without confirmation' do
        ClimateControl.modify TRADING_MODE: 'live', ALPACA_LIVE_API_KEY_ID: 'AK123',
                              ALPACA_LIVE_API_SECRET_KEY: 'secret', CONFIRM_LIVE_TRADING: 'no' do
          expect { described_class.new }.to raise_error(
            AlpacaService::SafetyError,
            'Live trading requires CONFIRM_LIVE_TRADING=yes environment variable'
          )
        end
      end
    end
  end

  describe '#trading_mode' do
    it 'returns the trading mode' do
      ClimateControl.modify TRADING_MODE: 'paper', ALPACA_PAPER_API_KEY_ID: 'PK123',
                            ALPACA_PAPER_API_SECRET_KEY: 'secret' do
        service = described_class.new
        expect(service.trading_mode).to eq('paper')
      end
    end
  end

  describe '#account_equity' do
    let(:service) do
      ClimateControl.modify TRADING_MODE: 'paper', ALPACA_PAPER_API_KEY_ID: 'PK123',
                            ALPACA_PAPER_API_SECRET_KEY: 'secret' do
        described_class.new
      end
    end
    let(:mock_account) { instance_double(Alpaca::Trade::Api::Account, equity: '50000.75') }

    context 'when API call is successful' do
      before do
        allow(mock_client).to receive(:account).and_return(mock_account)
      end

      it 'returns account equity as BigDecimal' do
        result = service.account_equity

        expect(result).to eq(BigDecimal('50000.75'))
        expect(result).to be_a(BigDecimal)
      end
    end
  end
end
# rubocop:enable RSpec/ContextWording
