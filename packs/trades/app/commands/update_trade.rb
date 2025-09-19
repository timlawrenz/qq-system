# frozen_string_literal: true

# UpdateTrade Command
#
# This command updates an existing trade with new attributes.
class UpdateTrade < GLCommand::Callable
  requires :trade
  allows :symbol, :executed_at, :side, :quantity, :price
  returns :trade

  validate :validate_side_if_present
  validate :validate_quantity_if_present
  validate :validate_price_if_present
  validate :validate_executed_at_if_present

  def call
    update_attributes = build_update_attributes

    context.trade.update!(update_attributes) if update_attributes.any?
  end

  private

  def build_update_attributes
    attributes = {}

    attributes[:symbol] = context.symbol.upcase if context.symbol.present?
    attributes[:executed_at] = parse_executed_at(context.executed_at) if context.executed_at.present?
    attributes[:side] = context.side.downcase if context.side.present?
    attributes[:quantity] = context.quantity.to_f if context.quantity.present?
    attributes[:price] = context.price.to_f if context.price.present?

    attributes
  end

  def validate_side_if_present
    return if context.side.blank?

    errors.add(:side, 'must be buy or sell') unless %w[buy sell].include?(context.side.downcase)
  end

  def validate_quantity_if_present
    return if context.quantity.blank?

    errors.add(:quantity, 'must be greater than 0') unless context.quantity.to_f.positive?
  rescue ArgumentError
    errors.add(:quantity, 'must be a valid number')
  end

  def validate_price_if_present
    return if context.price.blank?

    errors.add(:price, 'must be greater than 0') unless context.price.to_f.positive?
  rescue ArgumentError
    errors.add(:price, 'must be a valid number')
  end

  def validate_executed_at_if_present
    return if context.executed_at.blank?

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
