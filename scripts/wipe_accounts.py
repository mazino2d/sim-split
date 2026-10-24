"""One-off account wipe for the R-4 release (spec AC12).

Accounts created before R-4 never agreed to the privacy policy that adds
usage tracking, so at release time every account and all cloud data go:

1. Every Firebase Auth user.
2. Firestore: groups (with members, expenses, settlements, activity),
   invites and users.
3. The warehouse copy of that data in BigQuery (dataplatform-as-se1-prd,
   simsplit_raw): the tables data-platform's dlt load writes and its state,
   so the next load starts clean. error_reports and usage_events stay (they
   are not linked to these accounts).

Dry run by default: it only counts. Pass --yes to delete.

Setup (maintainer, personal account):
    gcloud --configuration=mazino2d auth application-default login
    gcloud auth application-default set-quota-project simsplit-as-se1-prd
    pip install firebase-admin google-cloud-firestore google-cloud-bigquery
    python3 scripts/wipe_accounts.py          # dry run
    python3 scripts/wipe_accounts.py --yes    # delete
"""

import argparse

import firebase_admin
from firebase_admin import auth
from google.cloud import bigquery, firestore

APP_PROJECT = "simsplit-as-se1-prd"
WAREHOUSE_PROJECT = "dataplatform-as-se1-prd"
RAW_DATASET = "simsplit_raw"
COLLECTIONS = ["groups", "invites", "users"]
DLT_TABLES = ["users", "groups", "members", "expenses", "settlements", "activity",
              "_dlt_loads", "_dlt_pipeline_state", "_dlt_version"]


def auth_users():
    page = auth.list_users()
    while page:
        yield from page.users
        page = page.get_next_page()


def main(delete):
    firebase_admin.initialize_app(options={"projectId": APP_PROJECT})
    db = firestore.Client(project=APP_PROJECT)
    bq = bigquery.Client(project=WAREHOUSE_PROJECT)
    verb = "Deleting" if delete else "Would delete"

    uids = [u.uid for u in auth_users()]
    print(f"{verb} {len(uids)} Auth users")
    if delete:
        for i in range(0, len(uids), 1000):
            result = auth.delete_users(uids[i:i + 1000])
            for error in result.errors:
                print(f"  failed {uids[i + error.index]}: {error.reason}")

    for name in COLLECTIONS:
        count = sum(1 for _ in db.collection(name).list_documents())
        print(f"{verb} Firestore {name}: {count} documents, with their subcollections")
        if delete:
            db.recursive_delete(db.collection(name))

    existing = {t.table_id for t in bq.list_tables(f"{WAREHOUSE_PROJECT}.{RAW_DATASET}")}
    for table in DLT_TABLES:
        if table not in existing:
            continue
        print(f"{verb} BigQuery {RAW_DATASET}.{table}")
        if delete:
            bq.delete_table(f"{WAREHOUSE_PROJECT}.{RAW_DATASET}.{table}", not_found_ok=True)

    if not delete:
        print("Dry run: nothing deleted. Run again with --yes.")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--yes", action="store_true", help="really delete")
    main(parser.parse_args().yes)
