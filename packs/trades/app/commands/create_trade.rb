# frozen_string_literal: true

# CreateTrade Command
#
# This command creates a new trade for a given algorithm.
class CreateTrade < GLCommand::Callable
  requires :algorithm, :symbol, :executed_at, :side, :quantity, :price
  returns :trade

  validates :symbol, presence: true
  validates :quantity, presence: true, numericality: { greater_than: 0 }
  validates :price, presence: true, numericality: { greater_than: 0 }
  validate :validate_executed_at
  validate :validate_side

  def call
    context.trade = Trade.create!(
      algorithm: context.algorithm,
      symbol: context.symbol.upcase,
      executed_at: parse_executed_at(context.executed_at),
      side: context.side.downcase,
      quantity: context.quantity.to_f,
      price: context.price.to_f
    )
  end

  private

  def validate_side
    return if context.side.blank?

    errors.add(:side, 'is not included in the list') unless %w[buy sell].include?(context.side.downcase)
  end

  def validate_executed_at
    parse_executed_at(context.executed_at)
  rescue ArgumentError => e
    errors.add(:executed_at, "invalid date/time format: #{e.message}")
  end

  def parse_executed_at(value)
    case value
    when DateTime, Time
      value
    when String
      DateTime.parse(value)
    else
      raise ArgumentError, 'must be a DateTime, Time, or parseable string'
    end
  end
end
