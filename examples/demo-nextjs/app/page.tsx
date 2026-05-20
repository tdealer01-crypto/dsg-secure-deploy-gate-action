export default function Page() {
  return (
    <main style={{ fontFamily: "system-ui", padding: 32 }}>
      <h1>DSG Secure Deploy Gate Demo</h1>
      <p>Use this demo app to test readiness and protected-route checks.</p>
      <ul>
        <li><code>/api/readiness</code> returns 200 and ok=true.</li>
        <li><code>/api/private-audit</code> returns 401 without auth.</li>
      </ul>
    </main>
  );
}
