# frozen_string_literal: true

module TradingStrategies
  # Service to calculate position sizes based on asset volatility (ATR)
  # Ensures consistent risk contribution from each position
  class VolatilitySizingService
    DEFAULT_ATR_PERIOD = 14
    DEFAULT_VOLATILITY_FALLBACK = 0.03 # 3% of price ATR fallback

    # @param net_scores [Hash<String, Float>] Map of ticker => net_score (-1.0 to 1.0)
    # @param total_equity [BigDecimal] Total account equity
    # @param risk_target_pct [Float] Target risk per trade (e.g., 0.01 for 1%)
    # @param atr_period [Integer] Lookback period for ATR calculation
    API_BATCH_SIZE = 50

    def initialize(net_scores:, total_equity:, risk_target_pct: 0.01, atr_period: DEFAULT_ATR_PERIOD)
      @net_scores = net_scores
      @total_equity = total_equity
      @risk_target_pct = risk_target_pct
      @atr_period = atr_period
      @alpaca_service = AlpacaService.new
      @current_price_cache = nil
    end

    # @return [Array<TargetPosition>]
    def call
      target_positions = []

      @net_scores.each do |ticker, score|
        next if score.zero?

        position = calculate_position_for_ticker(ticker, score)
        target_positions << position if position
      end

      target_positions
    end

    private

    def calculate_position_for_ticker(ticker, score)
      atr = calculate_atr(ticker)

      if atr.nil? || atr.zero?
        Rails.logger.warn("VolatilitySizingService: Could not calculate ATR for #{ticker}, skipping")
        return nil
      end

      price = fetch_current_price(ticker)
      return nil if price.nil?

      # Risk Unit = (Total Equity * Risk Target %) / ATR
      risk_amount = @total_equity * @risk_target_pct
      shares = (risk_amount / atr).floor

      # Scale by conviction score
      adjusted_shares = (shares * score.abs).floor

      create_target_position(ticker, score, adjusted_shares, atr, price)
    end

    def create_target_position(ticker, score, shares, atr, current_price)
      target_value = shares * current_price

      # Apply direction (Long/Short)
      target_value = -target_value if score.negative?

      TargetPosition.new(
        symbol: ticker,
        asset_type: :stock,
        target_value: target_value,
        details: {
          net_score: score,
          atr: atr,
          risk_target_pct: @risk_target_pct,
          shares: shares,
          implied_stop_loss: atr * 2
        }
      )
    end

    def calculate_atr(ticker)
      bars = fetch_bars_for_atr(ticker)
      fallback = fallback_atr_from_price(bars)

      # If we couldn't derive ATR from historical bars, fall back to a simple
      # percentage of the current price to avoid dropping the signal entirely.
      if fallback.nil?
        price = fetch_current_price(ticker)

        if price.nil?
          Rails.logger.warn(
            "VolatilitySizingService: Market data unavailable for #{ticker}, blocking asset for 7 days"
          )
          BlockedAsset.block_asset(symbol: ticker.to_s, reason: 'market_data_unavailable')
          return nil
        end

        fallback = price * DEFAULT_VOLATILITY_FALLBACK
      end

      return fallback if bars.size < @atr_period + 1

      true_ranges = calculate_true_ranges(bars)

      # Calculate ATR (Simple Moving Average of TRs for simplicity)
      recent_trs = true_ranges.last(@atr_period)
      return fallback if recent_trs.size < @atr_period

      recent_trs.sum / recent_trs.size
    end

    def fallback_atr_from_price(bars)
      return nil if bars.empty? || bars.last.close.nil?

      # Use a simple percentage of price as ATR fallback to avoid unrealistically
      # small absolute ATR values that would over-leverage tiny accounts.
      bars.last.close * DEFAULT_VOLATILITY_FALLBACK
    end

    def fetch_bars_for_atr(ticker)
      start_date = (@atr_period + 5).days.ago.to_date

      bars = HistoricalBar.for_symbol(ticker)
                          .where(timestamp: start_date..Date.current)
                          .order(timestamp: :asc)
                          .to_a

      bars = fetch_api_bars(ticker, start_date) if bars.size < @atr_period + 1

      bars
    end

    def fetch_api_bars(ticker, start_date)
      api_bars = @alpaca_service.get_bars(ticker, start_date: start_date, timeframe: '1Day')
      # Use a simple Struct instead of OpenStruct for performance and style
      bar_struct = Struct.new(:high, :low, :close)
      api_bars.map do |b|
        bar_struct.new(b[:high], b[:low], b[:close])
      end
    rescue StandardError => e
      Rails.logger.error("VolatilitySizingService: Failed to fetch bars for #{ticker}: #{e.message}")
      []
    end

    def calculate_true_ranges(bars)
      true_ranges = []
      bars.each_cons(2) do |prev, curr|
        high = curr.high
        low = curr.low
        prev_close = prev.close

        tr = [
          high - low,
          (high - prev_close).abs,
          (low - prev_close).abs
        ].max

        true_ranges << tr
      end
      true_ranges
    end

    def fetch_current_price(ticker)
      # Lazy batch prefetch of current prices for all tickers to reduce Alpaca calls
      prefetch_current_prices if @current_price_cache.nil?

      price = @current_price_cache[ticker.to_s]
      return price if price

      # Fallback: single-symbol fetch if ticker was not included or returned no data
      start_date = 5.days.ago.to_date
      bars = @alpaca_service.get_bars(ticker, start_date: start_date, timeframe: '1Day')
      return bars.last[:close] if bars.any?

      Rails.logger.warn("VolatilitySizingService: Could not get current price for #{ticker}, skipping")
      nil
    rescue StandardError => e
      Rails.logger.error("VolatilitySizingService: Failed to fetch current price for #{ticker}: #{e.message}")
      nil
    end

    def prefetch_current_prices
      tickers = @net_scores.keys.map(&:to_s)
      start_date = 5.days.ago.to_date
      @current_price_cache = {}

      tickers.each_slice(API_BATCH_SIZE) do |batch|
        bars_by_symbol = @alpaca_service.get_bars_multi(batch, start_date: start_date, timeframe: '1Day')
        bars_by_symbol.each do |sym, bars|
          next unless bars.any?

          @current_price_cache[sym] = bars.last[:close]
        end
      end
    rescue StandardError => e
      Rails.logger.error("VolatilitySizingService: Failed batch prefetch of current prices: #{e.message}")
      @current_price_cache ||= {}
    end
  end
end
