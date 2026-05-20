export async function GET(req: Request) {
  const auth = req.headers.get("authorization");

  if (!auth) {
    return Response.json(
      {
        ok: false,
        error: "Unauthorized",
      },
      { status: 401 },
    );
  }

  return Response.json({ ok: true, scope: "private-audit" });
}
