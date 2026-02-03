# Critical Account Safety Fix Required

**Priority**: 🔴 CRITICAL  
**Status**: Identified, awaiting implementation

## The Problem

Multiple code paths independently create `AlpacaService.new` and read `ENV['TRADING_MODE']`.  
This creates risk of accidentally mixing paper ($100k) and live ($1k) accounts.

## See Details

Read the full analysis: `/docs/CRITICAL_ACCOUNT_SAFETY_ISSUE.md`

## DO NOT RUN LIVE TRADING until this is fixed.
