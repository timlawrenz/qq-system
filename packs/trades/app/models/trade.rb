# frozen_string_literal: true

class Trade < ApplicationRecord
  belongs_to :algorithm

  validates :symbol, presence: true
  validates :executed_at, presence: true
  validates :side, presence: true, inclusion: { in: %w[buy sell] }
  validates :quantity, presence: true, numericality: { greater_than: 0 }
  validates :price, presence: true, numericality: { greater_than: 0 }
end
