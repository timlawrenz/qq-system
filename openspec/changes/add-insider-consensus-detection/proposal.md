# Change Proposal: Corporate Insider Consensus Detection

**Change ID**: `add-insider-consensus-detection`  
**Type**: Feature Enhancement  
**Status**: Draft  
**Priority**: Medium (Priority 3 in roadmap)  
**Estimated Effort**: 2-3 weeks  
**Created**: 2025-11-10  

---

## Why

The basic insider mimicry strategy (Priority 2) treats all insider trades equally. Academic research shows that when **multiple insiders** from the same company buy stock within a short time window, it's a significantly stronger signal than individual trades. This "consensus buying" indicates high conviction across the executive team and predicts better returns. This enhancement adds +2-4% annual alpha over the basic insider strategy by identifying and weighting these high-conviction signals.

---

## What Changes

### New Capabilities
- **Insider consensus detection** - Identify when 2+ insiders from same company buy within 30-day window
- **Conviction scoring** - Calculate consensus strength based on number of insiders, seniority, and transaction sizes
- **Position size boosting** - Increase allocation to consensus stocks (1.5-2.0x multiplier)
- **Behavioral shift detection** - Flag when a CEO makes first-ever open-market purchase (high signal)
- **Same-stock clustering** - Detect when unrelated insiders (different companies) buy same stock

### Technical Components
- **InsiderConsensusDetector service** - Analyzes insider trading patterns
- **InsiderConvictionScorer service** - Calculates conviction scores
- **BehavioralShiftDetector service** - Identifies significant behavioral changes
- **Enhanced portfolio command** - Extends GenerateInsiderMimicryPortfolio with consensus boost
- **Database enhancements** - Add insider_consensus_score to track stock-level conviction

### Breaking Changes
- None - enhances existing insider strategy with new filtering and weighting logic

---

## Impact

### Affected Specs
- `insider-trading` (MODIFIED) - Adds consensus detection requirements
- `trading-strategies` (MODIFIED) - Enhances insider portfolio generation with conviction scoring

### Affected Code
- Database: 1 migration adding consensus tracking fields
- Services: 3 new services in `packs/trading_strategies/app/services/`
- Commands: Enhance existing GenerateInsiderMimicryPortfolio
- Tests: ~50 new test cases

### Performance Impact
- Additional queries: Group by company to detect consensus (optimized with indexes)
- Strategy execution: Adds <2 seconds (consensus detection is O(n log n))
- No impact on data fetching (reuses existing insider trades)

### External Dependencies
- None - builds on existing insider trading data from Priority 2
- **Requires**: `add-corporate-insider-strategy` to be implemented first
