package ai.zenv.qudossl.haproxydemo;

import org.springframework.http.MediaType;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;

import java.net.InetAddress;
import java.net.UnknownHostException;
import java.time.Instant;
import java.util.LinkedHashMap;
import java.util.Map;

/**
 * The three demo endpoints:  /  (HTML), /health (JSON), /info (JSON).
 *
 * <p>Everything here is non-sensitive. The backend never sees or handles TLS;
 * it only reports what it is, so a customer can confirm the SAME application is
 * served before and after the QudoSSL migration of HAProxy.</p>
 */
@RestController
public class DemoController {

    private static final String APPLICATION = "QudoSSL HAProxy Migration Demo";
    private static final String VERSION = "1.0.0";
    private static final String TLS_TERMINATION = "HAProxy";
    private static final String BACKEND_PROTOCOL = "HTTP";

    @GetMapping(value = "/", produces = MediaType.TEXT_HTML_VALUE)
    public String home() {
        return """
            <!doctype html>
            <html lang="en">
            <head>
              <meta charset="utf-8">
              <meta name="viewport" content="width=device-width, initial-scale=1">
              <title>QudoSSL HAProxy Migration Demo</title>
              <style>
                :root { color-scheme: light dark; }
                body { font-family: system-ui, -apple-system, "Segoe UI", sans-serif;
                       margin: 0; background: #f4f4f4; color: #123a5c; }
                .wrap { max-width: 720px; margin: 0 auto; padding: 48px 24px; }
                .card { background: #fff; border: 1px solid #d1d1d1; padding: 32px; }
                h1 { font-size: 24px; margin: 0 0 4px; }
                .sub { color: #5b6472; margin: 0 0 28px; }
                dl { display: grid; grid-template-columns: 180px 1fr; gap: 10px 16px; margin: 0; }
                dt { color: #5b6472; font-size: 13px; text-transform: uppercase; letter-spacing: .04em; }
                dd { margin: 0; font-weight: 600; }
                .up { color: #15803d; }
                .links { margin-top: 28px; display: flex; gap: 12px; }
                a { color: #1d6a5b; text-decoration: none; border: 1px solid #1d6a5b; padding: 8px 14px; }
                a:hover { background: #1d6a5b; color: #fff; }
                footer { color: #9ca3af; font-size: 12px; margin-top: 24px; }
              </style>
            </head>
            <body>
              <div class="wrap">
                <div class="card">
                  <h1>QudoSSL Migration Demo</h1>
                  <p class="sub">Spring Boot Application</p>
                  <dl>
                    <dt>Application</dt><dd>QudoSSL HAProxy Migration Demo</dd>
                    <dt>Backend</dt><dd>Spring Boot</dd>
                    <dt>TLS Termination</dt><dd>HAProxy</dd>
                    <dt>Backend Protocol</dt><dd>HTTP</dd>
                    <dt>Status</dt><dd class="up">UP</dd>
                  </dl>
                  <div class="links">
                    <a href="/health">/health</a>
                    <a href="/info">/info</a>
                  </div>
                  <footer>TLS is terminated by HAProxy in front of this backend.
                    Migrate HAProxy to QudoSSL and this page is served over
                    post-quantum TLS &mdash; unchanged.</footer>
                </div>
              </div>
            </body>
            </html>
            """;
    }

    @GetMapping(value = "/health", produces = MediaType.APPLICATION_JSON_VALUE)
    public Map<String, String> health() {
        return Map.of("status", "UP");
    }

    @GetMapping(value = "/info", produces = MediaType.APPLICATION_JSON_VALUE)
    public Map<String, Object> info() {
        // LinkedHashMap to keep a stable, readable field order in the JSON.
        Map<String, Object> m = new LinkedHashMap<>();
        m.put("application", APPLICATION);
        m.put("version", VERSION);
        m.put("framework", "Spring Boot");
        m.put("javaVersion", System.getProperty("java.version"));
        m.put("hostname", hostname());
        m.put("timestamp", Instant.now().toString());
        m.put("tlsTermination", TLS_TERMINATION);
        m.put("backendProtocol", BACKEND_PROTOCOL);
        return m;
    }

    private static String hostname() {
        try {
            return InetAddress.getLocalHost().getHostName();
        } catch (UnknownHostException e) {
            return "unknown";
        }
    }
}
