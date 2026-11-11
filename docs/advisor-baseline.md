# Supabase advisor baseline

Project `siyxkombexmowlggxlrb`. Captured 2026-11-11 with `get_advisors` (read-only).

| Type | Findings | Breakdown |
| --- | --- | --- |
| Security | 45 | `rls_enabled_no_policy` 3 (`clients`, `deals`, `webhook_events`); `anon_security_definer_function_executable` 9; `authenticated_security_definer_function_executable` 32; `auth_leaked_password_protection` 1 |
| Performance | 108 | `unindexed_foreign_keys` 91; `unused_index` 15; `multiple_permissive_policies` 2 |
| Health | 0 | none |

The anon SECURITY DEFINER list: `get_landing_page`, `record_landing_view`, `rls_auto_enable`, `send_web_chat`,
`start_web_chat`, `submit_landing_form`, `unsubscribe_email`, `web_chat_config`, `web_chat_messages`.

## Expected changes (predictions; verify after each step)

| Step | Expected change |
| --- | --- |
| 0006b (step 5) | `rls_enabled_no_policy`: `clients` and `deals` clear. 3 becomes 1 |
| 0009 (step 9) | `anon_security_definer_function_executable`: 9 becomes 8 (`rls_auto_enable` removed). The eight remaining are the intended anon RPCs |
| 0010 (step 10) | No change expected. TRUNCATE is not an advisor lint. Verified by the ACL compare instead |
| 0008 (step 8) | `clients_readiness` is SECURITY INVOKER, so no new authenticated finding is expected |

Any other difference must be explained before the window closes.
