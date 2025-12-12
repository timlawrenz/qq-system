# frozen_string_literal: true

require 'ostruct'

module TradingStrategies
  # Service to calculate position sizes based on asset volatility (ATR)
  # Ensures consistent risk contribution from each position
  class VolatilitySizingService
    DEFAULT_ATR_PERIOD = 14
    DEFAULT_VOLATILITY_FALLBACK = 0.03 # 3% daily volatility fallback

    # @param net_scores [Hash<String, Float>] Map of ticker => net_score (-1.0 to 1.0)
    # @param total_equity [BigDecimal] Total account equity
    # @param risk_target_pct [Float] Target risk per trade (e.g., 0.01 for 1%)
    # @param atr_period [Integer] Lookback period for ATR calculation
    def initialize(net_scores:, total_equity:, risk_target_pct: 0.01, atr_period: DEFAULT_ATR_PERIOD)
      @net_scores = net_scores
      @total_equity = total_equity
      @risk_target_pct = risk_target_pct
      @atr_period = atr_period
      @alpaca_service = AlpacaService.new
    end

    # @return [Array<TargetPosition>]
    def call
      target_positions = []

      @net_scores.each do |ticker, score|
        next if score.zero?

        atr = calculate_atr(ticker)
        
        if atr.nil? || atr.zero?
          Rails.logger.warn("VolatilitySizingService: Could not calculate ATR for #{ticker}, skipping")
          next
        end

        # Risk Unit = (Total Equity * Risk Target %) / ATR
        # This gives the number of shares to buy/sell to risk exactly RiskTarget% of equity
        # if the price moves against us by 1 ATR.
        risk_amount = @total_equity * @risk_target_pct
        shares = (risk_amount / atr).floor

        # Scale by conviction score
        # If score is 0.5, we take half the risk unit
        adjusted_shares = (shares * score.abs).floor
        
        # Calculate target value (Notional)
        # We need current price. ATR calculation usually gives us recent price too.
        current_price = fetch_current_price(ticker)
        target_value = adjusted_shares * current_price
        
        # Apply direction (Long/Short)
        target_value = -target_value if score.negative?

        target_positions << TargetPosition.new(
          symbol: ticker,
          asset_type: :stock,
          target_value: target_value,
          details: {
            net_score: score,
            atr: atr,
            risk_target_pct: @risk_target_pct,
            shares: adjusted_shares,
            implied_stop_loss: atr * 2 # Example: 2 ATR stop
          }
        )
      end

      target_positions
    end

    private

    def calculate_atr(ticker)
      # Fetch historical bars
      # We need enough bars for ATR calculation + buffer
      # ATR-14 needs 15 days of data (for previous close)
      start_date = (@atr_period + 5).days.ago.to_date
      
      bars = HistoricalBar.for_symbol(ticker)
                          .where(timestamp: start_date..Date.current)
                          .order(timestamp: :asc)
                          .to_a

      # If not enough cached data, try fetching from API
      if bars.size < @atr_period + 1
        begin
          api_bars = @alpaca_service.get_bars(ticker, start_date: start_date, timeframe: '1Day')
          # We don't persist here to keep service pure, but in production we might want to cache
          # Converting hash to object-like structure for compatibility if needed, 
          # but HistoricalBar is an AR model. 
          # Let's just use the hash from API if cache is missing.
          bars = api_bars.map { |b| OpenStruct.new(b) } 
        rescue StandardError => e
          Rails.logger.error("VolatilitySizingService: Failed to fetch bars for #{ticker}: #{e.message}")
          return nil
        end
      end

      return nil if bars.size < @atr_period + 1

      # Calculate True Ranges
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

      # Calculate ATR (Simple Moving Average of TRs for simplicity, or Wilder's Smoothing)
      # Using Simple Average for MVP
      recent_trs = true_ranges.last(@atr_period)
      return nil if recent_trs.size < @atr_period

      recent_trs.sum / recent_trs.size
    end

    def fetch_current_price(ticker)
      # For MVP, use the close of the last bar
      # In production, this should be real-time quote
      # We can reuse the bars fetched for ATR
      start_date = 5.days.ago.to_date
      bars = @alpaca_service.get_bars(ticker, start_date: start_date, timeframe: '1Day')
      return bars.last[:close] if bars.any?
      
      # Fallback if no bars (shouldn't happen if ATR succeeded)
      raise "Could not get current price for #{ticker}"
    end
  end
end
