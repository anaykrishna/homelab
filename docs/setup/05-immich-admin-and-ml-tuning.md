# 05 — Immich admin setup + ML tuning for old hardware

1. As admin: Administration -> Users -> create 2–3 member accounts (one per person).
2. Administration -> Settings -> Machine Learning: keep Facial Recognition ON and Smart
   Search ON (8 GB RAM handles both). To halve load you may disable Smart Search.
3. Administration -> Settings -> Job Settings: set concurrency = 1 for
   "Face Detection", "Facial Recognition", and "Smart Search" (steady low CPU on the 2-core i3).
4. Expect the FIRST library scan to take several nightly windows; daily new photos are fast.
5. ML container already has a 3 GB memory limit (docker-compose.yml `mem_limit`).
