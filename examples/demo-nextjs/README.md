# DSG Secure Deploy Gate Demo Next.js App

Minimal endpoints for testing DSG Secure Deploy Gate.

## Endpoints

- `/api/readiness` returns HTTP 200 and `{ "ok": true }`.
- `/api/private-audit` returns HTTP 401 unless an `Authorization` header is present.

## Local run

```bash
npm install
npm run dev
```

Then test:

```bash
curl -i http://localhost:3000/api/readiness
curl -i http://localhost:3000/api/private-audit
```

## Workflow example

See `workflows/dsg-gate.example.yml`.
