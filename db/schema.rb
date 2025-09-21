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

ActiveRecord::Schema[8.0].define(version: 2025_09_21_004810) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "algorithms", force: :cascade do |t|
    t.string "name"
    t.text "description"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "analyses", force: :cascade do |t|
    t.bigint "algorithm_id", null: false
    t.date "start_date"
    t.date "end_date"
    t.string "status", default: "pending"
    t.jsonb "results"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["algorithm_id"], name: "index_analyses_on_algorithm_id"
    t.index ["status"], name: "index_analyses_on_status"
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

  create_table "quiver_trades", force: :cascade do |t|
    t.string "ticker"
    t.string "company"
    t.string "trader_name"
    t.string "trader_source"
    t.date "transaction_date"
    t.string "transaction_type"
    t.string "trade_size_usd"
    t.datetime "disclosed_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "trades", force: :cascade do |t|
    t.bigint "algorithm_id", null: false
    t.string "symbol", null: false
    t.datetime "executed_at", null: false
    t.string "side", null: false
    t.decimal "quantity", precision: 10, scale: 4, null: false
    t.decimal "price", precision: 10, scale: 4, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["algorithm_id"], name: "index_trades_on_algorithm_id"
    t.index ["executed_at"], name: "index_trades_on_executed_at"
    t.index ["side"], name: "index_trades_on_side"
    t.index ["symbol"], name: "index_trades_on_symbol"
  end

  add_foreign_key "analyses", "algorithms"
  add_foreign_key "trades", "algorithms"
end
