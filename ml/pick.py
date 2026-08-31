from db import fetch
rows = fetch("""
    select p.student_id, count(a.attempt_id) as n
      from profiles p join attempts a on a.student_id = p.student_id
     where p.cohort = 'synthetic-v1'
     group by p.student_id order by n desc limit 3
""")
for r in rows:
    print(str(r["student_id"]), r["n"])
