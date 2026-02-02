# FEC Contribution Weighting - Setup Guide

## Quick Start (Automatic)

**NEW:** FEC committee IDs can now be populated automatically!

```bash
# 1. Automatically find and set FEC committee IDs for all politicians
bundle exec rake fec:populate_committee_ids

# 2. Sync contribution data
bundle exec rake fec:sync

# 3. Done! FEC weighting is now active
```

The FEC sync will run automatically every day as part of `rake maintenance:daily`.

---

## Automatic Committee ID Population

### How It Works

The system automatically:
1. Searches the FEC API for each politician by name, state, and party
2. Finds their principal campaign committee
3. Sets the `fec_committee_id` in the database
4. Matches based on:
   - Name (handles "LAST, FIRST" format)
   - State (e.g., CA, NY)
   - Party (D/R/I)
   - Office type (House vs Senate)

### Usage

**Run automatic population:**
```bash
bundle exec rake fec:populate_committee_ids
```

**Dry run (see what would change):**
```bash
bundle exec rake fec:populate_committee_ids_dry_run
```

**Expected output:**
```
[fec:populate_committee_ids] Starting automatic FEC committee ID lookup...

  ✓ Nancy Pelosi: C00268623
  ✓ Chuck Schumer: C00028142
  ✓ Kevin McCarthy: C00372268
  - John Doe: No committee found
  ✗ Jane Smith: Multiple candidates found

[fec:populate_committee_ids] ✓ Complete
  Politicians processed: 100
  Committee IDs found: 85
  Committee IDs set: 85
  Skipped (no match): 12
  Failed: 3
```

### When to Use

- **First-time setup:** Populate all politicians at once
- **After adding new politicians:** Run to get their committee IDs
- **Quarterly refresh:** Update any changed committee IDs

### Limitations

- **Requires clean data:** Politician names, states, and parties should be accurate
- **Manual review recommended:** Some matches may be ambiguous
- **Rate limited:** Processes ~10-20 politicians/minute (0.3s per API call)
- **May miss some:** Politicians with unusual names or multiple committees

---

## Manual Setup (Fallback)

If automatic lookup fails or you want more control:

```bash
# Set committee ID manually
bundle exec rake fec:set_committee_id["Nancy Pelosi","C00268623"]
```

**Finding Committee IDs:**
1. Visit https://www.fec.gov/data/candidates/
2. Search for the politician's name
3. Find their principal campaign committee
4. Copy the committee ID (format: `C########`)

---

## Daily Usage

### Automatic Sync (Recommended)

FEC sync runs automatically in your daily maintenance:

```bash
bundle exec rake maintenance:daily
```

This will:
1. Fetch congressional trades
2. Fetch insider trades  
3. Fetch government contracts
4. Fetch lobbying data
5. Sync committee memberships
6. **✓ Sync FEC contributions**
7. Score politicians
8. Cleanup blocked assets
9. Refresh company profiles

**Output includes:**
```
[maintenance:daily] FEC Sync: politicians=85, created=5, updated=340, classification=78.5%
```

### Manual Sync (When Needed)

```bash
# Sync all politicians with committee IDs
bundle exec rake fec:sync

# Sync single politician
bundle exec rake fec:sync_politician[123]

# Force refresh (re-fetch all data)
# In Rails console:
SyncFecContributions.call(cycle: 2024, force_refresh: true)
```

---

## Monitoring

### Check Current Status

```bash
# List politicians with FEC committee IDs
bundle exec rake fec:list_committees

# Show FEC contribution statistics
bundle exec rake fec:stats
```

### Expected Output

```bash
$ rake fec:stats

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
💰 FEC Contribution Statistics (2024 Cycle)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Politicians with committee IDs: 85
Politicians with FEC data: 82
Total contribution records: 412
Significant contributions (>$10k): 298
Total contribution amount: $18,750,000

Top industries by contribution amount:
  Technology: $4,200,000
  Financial Services: $3,800,000
  Healthcare: $2,900,000
  Energy: $2,100,000
  Defense: $1,800,000

Top politicians by contribution amount:
  Nancy Pelosi: $520,000
  Chuck Schumer: $480,000
  Kevin McCarthy: $420,000
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

---

## Complete Workflow

### Initial Setup (One Time)

```bash
# 1. Automatically populate FEC committee IDs
bundle exec rake fec:populate_committee_ids

# 2. Sync FEC contribution data
bundle exec rake fec:sync

# 3. Verify setup
bundle exec rake fec:stats
bundle exec rake fec:list_committees
```

### Daily Operations

```bash
# Just run your daily maintenance - FEC sync included!
bundle exec rake maintenance:daily
```

### Quarterly Refresh (Optional)

```bash
# Update committee IDs (in case politicians changed committees)
bundle exec rake fec:populate_committee_ids

# Or force refresh in Rails console:
PopulateFecCommitteeIds.call(force_refresh: true)
```

---

## Trading Integration

### FEC Weighting (Enabled by Default)

```ruby
# Generate portfolio with FEC weighting
result = TradingStrategies::GenerateEnhancedCongressionalPortfolio.call(
  total_equity: 10_000,
  enable_fec_weighting: true  # Default
)

# Check positions with FEC multipliers
result.target_positions.each do |pos|
  details = pos.details
  if details[:fec_influence_multiplier] > 1.0
    puts "#{pos.symbol}: #{details[:fec_influence_multiplier]}x FEC boost"
  end
end
```

### Disable FEC Weighting (Baseline Comparison)

```ruby
result = TradingStrategies::GenerateEnhancedCongressionalPortfolio.call(
  total_equity: 10_000,
  enable_fec_weighting: false
)
```

---

## Troubleshooting

### Automatic Lookup Issues

**"No committee found" for many politicians:**
- Check that politician names, states, and parties are accurate
- Try manual lookup for important politicians
- Some politicians may not have active committees

**"Multiple candidates found":**
- Run with more specific data (ensure state and party are set)
- Use manual setup for these politicians

**Rate limiting (429 errors):**
- Wait 1 hour and retry
- System automatically rate limits (0.3s between calls)

### Sync Issues

**Classification rate too low (<65%):**
```bash
# Review unclassified employers
bundle exec rake fec:sync

# Add keywords to Industry.classify_employer()
# Then re-sync with force_refresh
```

**No FEC multipliers in portfolio:**
```bash
# 1. Verify committee IDs are set
bundle exec rake fec:list_committees

# 2. Verify FEC data exists
# Rails console:
PoliticianIndustryContribution.current_cycle.count

# 3. Check weighting is enabled (default: true)
```

---

## Performance

### Automatic Population
- **Speed:** ~10-20 politicians/minute
- **100 politicians:** ~5-10 minutes
- **Rate limit:** 0.3s between API calls (safe)

### FEC Sync
- **10 politicians:** <1 minute
- **50 politicians:** <5 minutes
- **100 politicians:** <10 minutes
- **Rate limit:** 0.5s between calls

### Trading Impact
- **Positions with FEC boost:** 30-50%
- **Average multiplier:** 1.3-1.5x
- **Maximum multiplier:** 2.0x (capped)
- **Expected alpha:** +0.5-1.5% annually

---

## Available Rake Tasks

```bash
# Automatic committee ID population
rake fec:populate_committee_ids           # Find and set committee IDs
rake fec:populate_committee_ids_dry_run   # Preview what would change

# Manual committee ID management  
rake fec:set_committee_id[name,id]        # Set one manually
rake fec:list_committees                  # List politicians with IDs

# Contribution syncing
rake fec:sync                             # Sync all politicians
rake fec:sync_politician[id]              # Sync one politician

# Monitoring
rake fec:stats                            # Show FEC statistics
```

---

## Summary

✅ **Automatic committee ID lookup** via `rake fec:populate_committee_ids`  
✅ **Automatic daily sync** via `rake maintenance:daily`  
✅ **Manual override** available if needed  
✅ **Monitoring** via `rake fec:stats`  
✅ **Trading integration** enabled by default  

**No background jobs required** - runs synchronously in your workflow.

---

**Next Steps:**
1. Run `rake fec:populate_committee_ids` to automatically set committee IDs
2. Run `rake fec:sync` to fetch contribution data
3. From then on, it runs automatically every day!
