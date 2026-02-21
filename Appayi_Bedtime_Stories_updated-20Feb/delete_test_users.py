import re
import sys
import firebase_admin
from firebase_admin import credentials, auth

DRY_RUN = "--dry" in sys.argv

# CHANGE THIS if needed:
EMAIL_REGEX = re.compile(r"^perf_\d+@example\.com$", re.IGNORECASE)

cred = credentials.Certificate("serviceAccountKey.json")
firebase_admin.initialize_app(cred)

def chunked(lst, n):
    for i in range(0, len(lst), n):
        yield lst[i:i + n]

def main():
    print(f"DRY_RUN: {DRY_RUN}")
    print(f"Deleting users matching: {EMAIL_REGEX.pattern}")

    total_matched = 0
    total_deleted = 0

    page = auth.list_users()
    while page:
        matched_uids = []
        for u in page.users:
            email = u.email or ""
            if EMAIL_REGEX.match(email):
                matched_uids.append(u.uid)

        if matched_uids:
            total_matched += len(matched_uids)

            if DRY_RUN:
                print(f"[DRY] Would delete {len(matched_uids)} users. Sample UIDs: {matched_uids[:10]}")
            else:
                for batch in chunked(matched_uids, 1000):
                    result = auth.delete_users(batch)
                    total_deleted += result.success_count
                    print(f"Deleted batch: success={result.success_count}, failed={result.failure_count}")
                    for err in result.errors:
                        print(f"  UID={batch[err.index]} error={err.reason}")

        page = page.get_next_page()

    print(f"Matched: {total_matched}")
    print(f"Deleted: {total_deleted}")
    print("Done.")

if __name__ == "__main__":
    main()
