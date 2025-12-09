# OpenSpec: Committee Data Integration

## Status: ✅ IMPLEMENTED (GitHub Alternative)

**Update**: ProPublica's Congress API is no longer available. We implemented an alternative solution using the free, open-source GitHub dataset from `unitedstates/congress-legislators`.

### Implementation Summary
- **Command**: `SyncCommitteeMembershipsFromGithub`
- **Data Source**: https://github.com/unitedstates/congress-legislators
- **Results**: 
  - 52 committees synced
  - 1,592 memberships created
  - 1,592 politicians matched via bioguide_id
- **Cost**: Free (open-source community project)
- **Updates**: Automated via GitHub Actions by maintainers
- **Commit**: a8681ae

---

## Original Problem

The Enhanced Congressional Strategy needs to score politicians based on their committee memberships to improve trade signal quality. Currently, we only have basic politician data without committee assignments.

## Solution Exploration

### Option 1: ProPublica Congress API ❌
- **Status**: No longer available
- ProPublica shut down their Congress API

### Option 2: OpenSecrets/CRP API ⚠️
- **Cost**: Paid API
- **Data**: Campaign finance + some committee data
- **Issue**: Not cost-effective for our current account size

### Option 3: GitHub Static Data ✅ CHOSEN
- **Source**: https://github.com/unitedstates/congress-legislators
- **Data**: YAML files with legislators, committees, and memberships
- **Maintained by**: @unitedstates community project
- **Updates**: Automated via GitHub Actions
- **Format**: Raw GitHub URLs for direct YAML access
- **Cost**: Free
- **Quality**: High - used by many government data projects

## Implementation Details

### Command: `SyncCommitteeMembershipsFromGithub`

**Location**: `packs/data_fetching/app/commands/sync_committee_memberships_from_github.rb`

**Returns**:
- `committees_processed`: Number of committees synced
- `memberships_created`: Number of committee memberships created
- `politicians_matched`: Number of politicians successfully matched
- `politicians_unmatched`: List of unmatched politician names

**Data Sources**:
```ruby
BASE_URL = "https://raw.githubusercontent.com/unitedstates/congress-legislators/main"
- committees-current.yaml      # Committee definitions
- committee-membership-current.yaml  # Current memberships
- legislators-current.yaml     # Legislator details with bioguide IDs
```

**Matching Strategy**:
1. Build bioguide_id → legislator map from GitHub data
2. Match GitHub legislators to our `PoliticianProfile` records via `bioguide_id`
3. Create `CommitteeMembership` records for matched politicians
4. Track unmatched politicians for review (327 unmatched = historical or not in our DB)

**Database Tables Used**:
- `Committee` (code, name, chamber, description, url, jurisdiction)
- `CommitteeMembership` (politician_profile_id, committee_id, start_date, end_date)
- `PoliticianProfile` (bioguide_id for matching)

## Usage

### Manual Sync
```ruby
result = SyncCommitteeMembershipsFromGithub.call

if result.success?
  puts "Synced #{result.memberships_created} memberships"
  puts "Matched #{result.politicians_matched} politicians"
  puts "Unmatched: #{result.politicians_unmatched.count}"
end
```

### Scheduled Job (Future)
We should add this to daily_trading.sh or create a weekly cron job to keep committee data fresh.

## Future Enhancements

### Automation
- [ ] Add to daily_trading.sh or separate weekly job
- [ ] Monitor for GitHub repo updates (they use GitHub Actions to update data)
- [ ] Alert if sync finds 0 memberships (data issue)

### Data Quality
- [ ] Review 327 unmatched politicians
- [ ] Add bioguide_id to more PoliticianProfile records
- [ ] Track historical committee memberships (end_date field exists)

### Integration with Strategy
- [ ] Update `ScorePoliticiansJob` to use committee data
- [ ] Weight trades based on relevant committee memberships
- [ ] Filter trades from politicians on finance/banking committees more heavily

## Benefits

1. **Cost**: $0 vs $50/month for alternatives
2. **Reliability**: Community-maintained, automated updates
3. **Data Quality**: High - same source many gov data sites use
4. **Integration**: Already working with 1,592 memberships synced
5. **Future-proof**: Open source, unlikely to disappear

## Notes

- GitHub data updates regularly but not real-time
- Good enough for daily trading strategy needs
- Can supplement with other sources later if needed
- This unblocks Enhanced Congressional Strategy completion
