# frozen_string_literal: true

class Algorithm < ApplicationRecord
  validates :name, presence: true
  validates :description, presence: true
end
