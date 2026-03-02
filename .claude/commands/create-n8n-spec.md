---
name: create-n8n-spec
description: Researches and generates a detailed implementation spec for an n8n automation.
user-invocable: true
argument-hint: "Short description of the automation (e.g., 'Lead Enrichment Pipeline')"
allowed-tools: Read, Write, Glob, Skill,
  - mcp__n8n-mcp__tools_documentation
  - mcp__n8n-mcp__search_nodes
  - mcp__n8n-mcp__get_node
  - mcp__n8n-mcp__search_templates
  - mcp__n8n-mcp__get_template
  - mcp__n8n-mcp__validate_node
  - mcp__n8n-mcp__list_workflows
  - mcp__claude_ai_n8n__search_workflows
  - mcp__claude_ai_n8n__get_workflow_details
  - mcp__postgres__list_schemas
  - mcp__postgres__list_objects
  - mcp__postgres__get_object_details
  - mcp__postgres__explain_query
  - mcp__postgres__analyze_workload_indexes
  - mcp__postgres__analyze_query_indexes
  - mcp__plugin_context7_context7__resolve-library-id
  - mcp__plugin_context7_context7__query-docs
  - read_file
  - write_file
  - list_files
---
# n8n Automation Architect Skill

You are an expert n8n automation architect. You are able to delegate analysis and research tasks to the subagent `n8n-workflow-expert` if it's needed. Your task is to research and produce a detailed, implementation-ready spec for the automation described in: **$ARGUMENTS**.  

User input: $ARGUMENTS

## Step 1. Parse arguments

Extract from the user input:
1. `automation_title` – human-readable title in Title Case (e.g. "Lead Enrichment Pipeline").
2. `automation_slug` – kebab-case (e.g. `lead-enrichment-pipeline`).
3. `automation_intent` – a one-sentence summary of the goal.

## Step 2: Parallel Research Phase

Do NOT skip research steps. Use subagent delegation to run in parallel when possible. Run the following checks to ensure technical accuracy:

### 2a. n8n Node Discovery
- Use `mcp__n8n-mcp__search_nodes` for relevant nodes. 
- Use `mcp__n8n-mcp__get_node` (detail: "standard") to find required credentials and parameters.
Search for at least 2-3 different keyword combinations related to the task. For the top candidate nodes, call `mcp__n8n-mcp__get_node` with `detail: "standard"`.

### 2b. Template discovery
- Search templates with `mcp__n8n-mcp__search_templates` (keyword/task mode).
- Review 1-2 relevant templates with `mcp__n8n-mcp__get_template`.
Use `mcp__n8n-mcp__search_templates` to find existing templates that are similar to the requested automation. Get the most relevant templates with `mcp__n8n-mcp__get_template` in `nodes_only` mode to understand the node composition pattern.

### 2c. Documentation Lookup
- Resolve n8n library via `mcp__plugin_context7_context7__resolve-library-id`.
- Query `mcp__plugin_context7_context7__query-docs` for trigger patterns and complex expressions.
Use `mcp__plugin_context7_context7__resolve-library-id` to find the n8n library, then query documentation relevant to:
- The trigger pattern (webhook, schedule, etc.)
- Main integration nodes identified in 2a.
- Any expressions, error handling, or sub-workflow patterns.

### 2d. Data Persistence (If applicable)
Use `mcp__postgres__*` tools to check what schemas, tables and database objects exist. Use postgresql-table-design skill if needed.

### 2e. Pattern guidance
Use the `Skill` tool to invoke relevant skills:
- `n8n-workflow-patterns` to identify right architectural pattern for the automation,
- `n8n-node-configuration` when configuring nodes, understanding property dependencies and AI workflows,
- `n8n-expression-syntax` for correct n8n expression syntax and common patterns,
- `n8n-mcp-tools-expert` when searching for nodes, validating configurations, accessing templates,
- `n8n-code-javascript` and `n8n-code-python` for code nodes.

## Step 3: Synthesis
Generate the spec file at `specs/<automation_slug>.md`. Do not write generic placeholders. Every node name, credential type, parameter name, and expression must be based on factual research. Read `specs/template-n8n.md`. If it does not exist, use the structure below:

```markdown
# Spec: <automation_title>

**Slug:** <automation_slug>
**Date:** <today>
**Status:** Draft

## Summary
<Description of improvement/goal>

## Trigger
- **Type:** [Webhook / Schedule / Manual / Event]
- **Node:** `<exact node type from research>`
- **Configuration:** <key parameters, path, method, cron expression, etc.>

## Node Pipeline
Ordered list of nodes with exact types confirmed by research:

| # | Node Name | Type | Purpose | Key Parameters |
|---|-----------|------|---------|----------------|
| 1 | <Name>    |<Type>|<Purpose>|<Params>        |

## Control flow / Data Flow
Describe what data enters, how it transforms at each step, and what exits.
Include specific `$json` field names where known.

## Credentials Required
List all credentials the workflow needs (confirmed via get_node research):
- `<credentialType>` - for <node name> - where to configure in n8n

## Database Integration
*(omit this if not applicable)*
- **Tables used:** list with purpose
- **Operations:** insert / select / vector search / realtime
- **Schema notes:** any new tables or columns needed

## Error Handling
- Which nodes need `continueOnFail: true` or error-branching
- Recommended error-branching or sub-workflow pattern