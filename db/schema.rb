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

ActiveRecord::Schema[8.0].define(version: 2025_12_08_173140) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "algorithms", force: :cascade do |t|
    t.string "name"
    t.text "description"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "alpaca_orders", force: :cascade do |t|
    t.uuid "alpaca_order_id", null: false
    t.bigint "quiver_trade_id"
    t.string "symbol", null: false
    t.string "side", null: false
    t.string "status", null: false
    t.decimal "qty", precision: 10, scale: 4
    t.decimal "notional", precision: 10, scale: 4
    t.string "order_type"
    t.string "time_in_force"
    t.datetime "submitted_at"
    t.datetime "filled_at"
    t.decimal "filled_avg_price", precision: 10, scale: 4
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "trading_mode", default: "paper", null: false
    t.index ["alpaca_order_id"], name: "index_alpaca_orders_on_alpaca_order_id", unique: true
    t.index ["quiver_trade_id"], name: "index_alpaca_orders_on_quiver_trade_id"
    t.index ["side"], name: "index_alpaca_orders_on_side"
    t.index ["status"], name: "index_alpaca_orders_on_status"
    t.index ["symbol"], name: "index_alpaca_orders_on_symbol"
    t.index ["trading_mode"], name: "index_alpaca_orders_on_trading_mode"
  end

  create_table "analyses", force: :cascade do |t|
    t.bigint "algorithm_id", null: false
    t.date "start_date"
    t.date "end_date"
    t.string "status", default: "pending"
    t.jsonb "results"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "trading_mode", default: "paper", null: false
    t.index ["algorithm_id"], name: "index_analyses_on_algorithm_id"
    t.index ["status"], name: "index_analyses_on_status"
    t.index ["trading_mode"], name: "index_analyses_on_trading_mode"
  end

  create_table "committee_industry_mappings", force: :cascade do |t|
    t.bigint "committee_id", null: false
    t.bigint "industry_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["committee_id"], name: "index_committee_industry_mappings_on_committee_id"
    t.index ["industry_id"], name: "index_committee_industry_mappings_on_industry_id"
  end

  create_table "committee_memberships", force: :cascade do |t|
    t.bigint "politician_profile_id", null: false
    t.bigint "committee_id", null: false
    t.date "start_date"
    t.date "end_date"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["committee_id"], name: "index_committee_memberships_on_committee_id"
    t.index ["politician_profile_id"], name: "index_committee_memberships_on_politician_profile_id"
  end

  create_table "committees", force: :cascade do |t|
    t.string "code"
    t.string "name"
    t.string "chamber"
    t.text "description"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["code"], name: "index_committees_on_code", unique: true
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

  create_table "industries", force: :cascade do |t|
    t.string "name"
    t.string "sector"
    t.text "description"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["name"], name: "index_industries_on_name", unique: true
  end

  create_table "politician_profiles", force: :cascade do |t|
    t.string "name"
    t.string "bioguide_id"
    t.string "party"
    t.string "state"
    t.decimal "quality_score"
    t.integer "total_trades"
    t.integer "winning_trades"
    t.decimal "average_return"
    t.datetime "last_scored_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["bioguide_id"], name: "index_politician_profiles_on_bioguide_id", unique: true
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

  create_table "solid_queue_blocked_executions", force: :cascade do |t|
    t.bigint "job_id", null: false
    t.string "queue_name", null: false
    t.integer "priority", default: 0, null: false
    t.string "concurrency_key", null: false
    t.datetime "expires_at", null: false
    t.datetime "created_at", null: false
    t.index ["concurrency_key", "priority", "job_id"], name: "index_solid_queue_blocked_executions_for_release"
    t.index ["expires_at", "concurrency_key"], name: "index_solid_queue_blocked_executions_for_maintenance"
    t.index ["job_id"], name: "index_solid_queue_blocked_executions_on_job_id", unique: true
  end

  create_table "solid_queue_claimed_executions", force: :cascade do |t|
    t.bigint "job_id", null: false
    t.bigint "process_id"
    t.datetime "created_at", null: false
    t.index ["job_id"], name: "index_solid_queue_claimed_executions_on_job_id", unique: true
    t.index ["process_id", "job_id"], name: "index_solid_queue_claimed_executions_on_process_id_and_job_id"
  end

  create_table "solid_queue_failed_executions", force: :cascade do |t|
    t.bigint "job_id", null: false
    t.text "error"
    t.datetime "created_at", null: false
    t.index ["job_id"], name: "index_solid_queue_failed_executions_on_job_id", unique: true
  end

  create_table "solid_queue_jobs", force: :cascade do |t|
    t.string "queue_name", null: false
    t.string "class_name", null: false
    t.text "arguments"
    t.integer "priority", default: 0, null: false
    t.string "active_job_id"
    t.datetime "scheduled_at"
    t.datetime "finished_at"
    t.string "concurrency_key"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["active_job_id"], name: "index_solid_queue_jobs_on_active_job_id"
    t.index ["class_name"], name: "index_solid_queue_jobs_on_class_name"
    t.index ["finished_at"], name: "index_solid_queue_jobs_on_finished_at"
    t.index ["queue_name", "finished_at"], name: "index_solid_queue_jobs_for_filtering"
    t.index ["scheduled_at", "finished_at"], name: "index_solid_queue_jobs_for_alerting"
  end

  create_table "solid_queue_pauses", force: :cascade do |t|
    t.string "queue_name", null: false
    t.datetime "created_at", null: false
    t.index ["queue_name"], name: "index_solid_queue_pauses_on_queue_name", unique: true
  end

  create_table "solid_queue_processes", force: :cascade do |t|
    t.string "kind", null: false
    t.datetime "last_heartbeat_at", null: false
    t.bigint "supervisor_id"
    t.integer "pid", null: false
    t.string "hostname"
    t.text "metadata"
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.index ["last_heartbeat_at"], name: "index_solid_queue_processes_on_last_heartbeat_at"
    t.index ["name", "supervisor_id"], name: "index_solid_queue_processes_on_name_and_supervisor_id", unique: true
    t.index ["supervisor_id"], name: "index_solid_queue_processes_on_supervisor_id"
  end

  create_table "solid_queue_ready_executions", force: :cascade do |t|
    t.bigint "job_id", null: false
    t.string "queue_name", null: false
    t.integer "priority", default: 0, null: false
    t.datetime "created_at", null: false
    t.index ["job_id"], name: "index_solid_queue_ready_executions_on_job_id", unique: true
    t.index ["priority", "job_id"], name: "index_solid_queue_poll_all"
    t.index ["queue_name", "priority", "job_id"], name: "index_solid_queue_poll_by_queue"
  end

  create_table "solid_queue_recurring_executions", force: :cascade do |t|
    t.bigint "job_id", null: false
    t.string "task_key", null: false
    t.datetime "run_at", null: false
    t.datetime "created_at", null: false
    t.index ["job_id"], name: "index_solid_queue_recurring_executions_on_job_id", unique: true
    t.index ["task_key", "run_at"], name: "index_solid_queue_recurring_executions_on_task_key_and_run_at", unique: true
  end

  create_table "solid_queue_recurring_tasks", force: :cascade do |t|
    t.string "key", null: false
    t.string "schedule", null: false
    t.string "command", limit: 2048
    t.string "class_name"
    t.text "arguments"
    t.string "queue_name"
    t.integer "priority", default: 0
    t.boolean "static", default: true, null: false
    t.text "description"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["key"], name: "index_solid_queue_recurring_tasks_on_key", unique: true
    t.index ["static"], name: "index_solid_queue_recurring_tasks_on_static"
  end

  create_table "solid_queue_scheduled_executions", force: :cascade do |t|
    t.bigint "job_id", null: false
    t.string "queue_name", null: false
    t.integer "priority", default: 0, null: false
    t.datetime "scheduled_at", null: false
    t.datetime "created_at", null: false
    t.index ["job_id"], name: "index_solid_queue_scheduled_executions_on_job_id", unique: true
    t.index ["scheduled_at", "priority", "job_id"], name: "index_solid_queue_dispatch_all"
  end

  create_table "solid_queue_semaphores", force: :cascade do |t|
    t.string "key", null: false
    t.integer "value", default: 1, null: false
    t.datetime "expires_at", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["expires_at"], name: "index_solid_queue_semaphores_on_expires_at"
    t.index ["key", "value"], name: "index_solid_queue_semaphores_on_key_and_value"
    t.index ["key"], name: "index_solid_queue_semaphores_on_key", unique: true
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

  add_foreign_key "alpaca_orders", "quiver_trades"
  add_foreign_key "analyses", "algorithms"
  add_foreign_key "committee_industry_mappings", "committees"
  add_foreign_key "committee_industry_mappings", "industries"
  add_foreign_key "committee_memberships", "committees"
  add_foreign_key "committee_memberships", "politician_profiles"
  add_foreign_key "solid_queue_blocked_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_claimed_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_failed_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_ready_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_recurring_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_scheduled_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "trades", "algorithms"
end
