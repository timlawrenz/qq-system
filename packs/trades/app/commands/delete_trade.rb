# frozen_string_literal: true

# DeleteTrade Command
#
# This command deletes an existing trade.
class DeleteTrade < GLCommand::Callable
  requires :trade
  returns :trade

  def call
    context.trade.destroy!
  end
end
