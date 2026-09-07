package ai.zenv.qudossl.nginxdemo;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;

/**
 * QudoSSL NGINX Migration Demo — backend.
 *
 * <p>A deliberately minimal Spring Boot service that speaks plain HTTP on
 * port 8080. It has no TLS of its own: TLS is terminated by NGINX in front of
 * it. The whole point of the demo is that this application does not change when
 * you migrate the NGINX TLS-termination layer to QudoSSL — the same HTTP
 * backend is served first over classical TLS, then over post-quantum TLS.</p>
 */
@SpringBootApplication
public class DemoApplication {
    public static void main(String[] args) {
        SpringApplication.run(DemoApplication.class, args);
    }
}
