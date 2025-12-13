# GitHub Committee Data Sync Strategy

## Current Implementation (Phase 1)

We're using the **unitedstates/congress-legislators** GitHub repository as our data source for committee memberships.

**Repository**: https://github.com/unitedstates/congress-legislators  
**Data Files**:
- `legislators-current.yaml` - Current legislators with bioguide IDs
- `committees-current.yaml` - Committee definitions
- `committee-membership-current.yaml` - Current committee assignments

**Update Frequency**: Community maintains this repo regularly (typically weekly during session)

## How to Keep Data Up to Date

### Manual Sync (Current)

Run the sync job manually when needed:

```bash
# Via Rails console
bundle exec rails runner "SyncCommitteeMembershipsFromGithubJob.perform_now"

# Or via command
bundle exec rails runner "SyncCommitteeMembershipsFromGithub.call"
```

**When to run**:
- Initial setup (today)
- After new Congress session starts (every 2 years)
- When committee assignments change (mid-session)
- Monthly for ongoing updates

### Automated Sync (Recommended for Production)

**Option 1: Cron Job (Simple)**

Add to your cron (or system scheduler):

```bash
# Run every Sunday at 3 AM
0 3 * * 0 cd /path/to/qq-system && bin/rails runner "SyncCommitteeMembershipsFromGithubJob.perform_now"
```

**Option 2: Rails Scheduled Job (Better)**

Use a job scheduler gem like:
- `whenever` - Cron-based scheduling
- `rufus-scheduler` - In-process scheduler
- `sidekiq-cron` - If using Sidekiq
- `solid_queue` recurring tasks - Built into Rails 8

Example with SolidQueue (already in use):

```ruby
# config/recurring.yml
production:
  sync_committee_memberships:
    class: SyncCommitteeMembershipsFromGithubJob
    queue: default
    schedule: "0 3 * * 0" # Every Sunday at 3 AM
```

**Option 3: GitHub Webhooks (Advanced)**

Monitor the unitedstates/congress-legislators repo for changes:

1. Create webhook endpoint in Rails
2. Subscribe to GitHub repo push events
3. Trigger sync when data files change
4. Near real-time updates!

**Complexity**: Medium  
**Benefit**: Automatic updates when source data changes

### Monitoring Data Freshness

Add a check to track when data was last synced:

```ruby
# In PoliticianProfile or Committee model
def self.committee_data_age
  last_sync = CommitteeMembership.maximum(:updated_at)
  return "Never synced" unless last_sync
  
  days_old = (Time.current - last_sync) / 1.day
  "#{days_old.round} days old"
end
```

Add to daily_trading.sh:

```bash
echo "Committee data age: "
bundle exec rails runner "puts CommitteeMembership.maximum(:updated_at)"
```

### Data Staleness Alerts

**Warning Levels**:
- 🟢 **0-7 days**: Fresh, no action needed
- 🟡 **7-30 days**: Acceptable, consider sync soon
- 🟠 **30-60 days**: Getting stale, sync recommended
- 🔴 **60+ days**: Very stale, sync required

**Alert Implementation**:

```ruby
# In daily_trading.sh or monitoring script
days_since_sync = (Time.current - CommitteeMembership.maximum(:updated_at)) / 1.day

if days_since_sync > 60
  puts "⚠️  WARNING: Committee data is #{days_since_sync.round} days old!"
  puts "    Run: SyncCommitteeMembershipsFromGithubJob.perform_now"
elsif days_since_sync > 30
  puts "⚠️  Committee data is #{days_since_sync.round} days old (consider updating)"
end
```

## Future Improvements (Phase 2)

### Option 1: Migrate to Congress.gov API

If we need real-time data or more control:

**URL**: https://api.congress.gov/v3/  
**Cost**: Free with API key  
**Benefit**: Official source, more current, richer data  
**Effort**: 2-3 hours to implement

**When to do this**:
- If GitHub repo becomes unmaintained
- If we need daily updates
- If we need historical tracking
- If we expand to bill sponsorship tracking

### Option 2: Hybrid Approach

- **GitHub data**: Baseline sync (monthly)
- **Congress.gov API**: Delta updates (weekly)
- **Best of both**: Reliability + Freshness

### Option 3: Local Caching

Store downloaded YAML files locally:

```ruby
# packs/data_fetching/app/services/github_legislators_cache.rb
class GitHubLegislatorsCache
  CACHE_DIR = Rails.root.join("tmp", "github_legislators_cache")
  
  def fetch_with_cache(filename, max_age: 1.week)
    cache_file = CACHE_DIR.join(filename)
    
    # Use cache if fresh
    if cache_file.exist? && cache_file.mtime > max_age.ago
      return File.read(cache_file)
    end
    
    # Download and cache
    content = download_from_github(filename)
    FileUtils.mkdir_p(CACHE_DIR)
    File.write(cache_file, content)
    content
  end
end
```

**Benefits**:
- Faster syncs (no repeated downloads)
- Works offline for development
- Reduces GitHub API load

## Recommended Setup for Your $1k Account

**Phase 1** (This Week):
1. ✅ Run initial sync (today)
2. ✅ Verify committee filter works
3. ✅ Test enhanced strategy

**Phase 2** (This Month):
1. Add monthly cron job
2. Add data age monitoring to daily_trading.sh
3. Document sync procedure in README

**Phase 3** (Next Quarter):
1. Evaluate if monthly updates are sufficient
2. Consider Congress.gov API if needed
3. Add historical tracking if performance proves strategy

## Manual Sync Procedure

**When to manually sync**:
- After major committee reshuffles
- New Congress session (every 2 years in January)
- When you notice committee filter not working as expected

**How to sync**:

```bash
# 1. Check current data age
bundle exec rails runner "puts 'Last sync: ' + CommitteeMembership.maximum(:updated_at).to_s"

# 2. Run sync
bundle exec rails runner "result = SyncCommitteeMembershipsFromGithub.call; puts result.value.inspect"

# 3. Verify results
bundle exec rails runner "puts 'Total memberships: ' + CommitteeMembership.count.to_s"
bundle exec rails runner "puts 'Politicians with committees: ' + CommitteeMembership.distinct.count(:politician_profile_id).to_s"

# 4. Test enhanced strategy
./test_enhanced_strategy.sh
```

## Data Source Health Check

Monitor the GitHub repo:

**Repo**: https://github.com/unitedstates/congress-legislators  
**Check**:
- Last commit date (should be < 1 month)
- Open issues (should be managed)
- Stars/watchers (indicator of community health)

**As of Dec 2025**:
- Stars: 2.4k+
- Last updated: Active
- Maintained by: Civic tech community
- Status: ✅ Healthy

**Backup plan**: If repo becomes unmaintained, switch to Congress.gov API (code structure already supports swapping data sources)

## Cost Comparison

| Solution | Setup Time | Monthly Cost | Update Frequency | Maintenance |
|----------|-----------|--------------|------------------|-------------|
| GitHub Static (current) | 1 hour | $0 | Weekly (auto) | Manual sync |
| GitHub + Cron | 1.5 hours | $0 | Weekly (auto) | Automated |
| Congress.gov API | 3 hours | $0 | Daily | Automated |
| Hybrid | 4 hours | $0 | Daily | Automated |

**Recommendation for now**: GitHub + Manual sync (what we're implementing today)

**Upgrade path**: Add cron job next week if daily trading goes well

---

**Created**: 2025-12-09  
**Last Updated**: 2025-12-09  
**Next Review**: After initial sync completes successfully
