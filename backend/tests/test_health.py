def test_health(client):
    assert client.get("/health").json() == {"status": "ok"}


def test_dashboard_origin_is_allowed(client):
    r = client.options("/v1/staff/login", headers={
        "Origin": "http://localhost:5173", "Access-Control-Request-Method": "POST"})
    assert r.headers.get("access-control-allow-origin") == "http://localhost:5173"


def test_other_origins_are_not(client):
    r = client.options("/v1/staff/login", headers={
        "Origin": "https://evil.example", "Access-Control-Request-Method": "POST"})
    assert "access-control-allow-origin" not in r.headers
