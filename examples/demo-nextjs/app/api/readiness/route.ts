export async function GET() {
  return Response.json({
    ok: true,
    service: "dsg-secure-deploy-gate-demo",
    timestamp: new Date().toISOString(),
  });
}
