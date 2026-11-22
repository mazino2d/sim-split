# crm/ — notifications as code (R-9)

Every message SimSplit sends, who gets it and the limits that keep it calm.
[`services/crm`](../services/crm) runs this config. The spec is
[R-9](../docs/product/specs/R-9-notifications-crm.md) and the plan is
[R-9](../docs/implementations/R-9-notifications-crm.md).

| Path | What it holds |
| --- | --- |
| `policy.yaml` | Kill switch, quiet hours, weekly cap. Can be stricter than `services/crm/src/calm.ts`, never looser |
| `categories.yaml` | Kinds of messages. Each is a switch in Settings → Notifications and an Android channel |
| `traits.yaml` | The user traits audiences may use (dbt model `simsplit_crm.user_traits`) |
| `triggers/` | Messages sent when something happens in a group (activity entries) |
| `schedules/` | Recurring messages, in device time, at most weekly |
| `campaigns/` | One-off notices: push and/or an in-app banner, between `send_at` and `ends_at` |
| `audiences/` | Named `all` / `any` rules over traits. No SQL |
| `templates/` | EN + VI copy in ICU MessageFormat, the same syntax as the app's ARB files |

Each file under a folder holds one item, and its name is the item's `id`.

## Changing what is sent

1. Edit or add files and open a PR.
2. The **CRM config** check validates every file and comments the plan on the PR:
   what changes, a preview of each changed message in EN and VI, and each audience
   in plain words.
3. To ship it, comment **`crm apply`** on the PR (a repo admin, once every check is
   green). `crm_apply.yml` squash-merges it and deploys the same image to **dev**, then
   **prd**, and comments the result on the PR. A refused apply says why.
4. A plain merge deploys to **dev** only. A campaign goes out on dev at the next tick
   (within 15 minutes); on prd it follows `send_at`. To ship what is already on main,
   comment `crm apply` on any merged PR: it deploys the latest main.

To stop everything, set `kill_switch: true` in a PR. In an emergency, move the
Cloud Run service `crm` to its previous revision instead.

Run the checks locally:

```sh
npm ci --prefix services/crm
npm --prefix services/crm run -s crm -- validate
npm --prefix services/crm run -s crm -- render
npm --prefix services/crm run -s crm -- plan --base <a copy of crm/ from main>
```
