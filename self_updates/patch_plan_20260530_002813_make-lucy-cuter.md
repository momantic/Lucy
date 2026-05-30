# Lucy Patch Plan

Patch name: make-lucy-cuter

## Purpose

This file is a proposed patch plan. It is not automatically applied.

## Current safe patch flow

1. Lucy creates this patch plan.
2. User reviews it.
3. Lucy can later implement an approved patch applier.
4. Lucy must backup files before applying.
5. Lucy must compile after applying.
6. Lucy must roll back on compile failure.

## Target

Requested patch:
make-lucy-cuter

## Notes

For now, Lucy only supports safe built-in apply commands:
- /apply hide-command
- /apply clean-memory

Future patch applier should only edit files inside:
/Users/michaelzheng/lucy
