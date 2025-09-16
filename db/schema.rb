# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.0].define(version: 2025_09_16_004542) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "algorithms", force: :cascade do |t|
    t.string "name"
    t.text "description"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "historical_bars", force: :cascade do |t|
    t.string "symbol", null: false
    t.datetime "timestamp", null: false
    t.decimal "open", precision: 10, scale: 4, null: false
    t.decimal "high", precision: 10, scale: 4, null: false
    t.decimal "low", precision: 10, scale: 4, null: false
    t.decimal "close", precision: 10, scale: 4, null: false
    t.integer "volume", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["symbol", "timestamp"], name: "index_historical_bars_on_symbol_and_timestamp", unique: true
  end
end
