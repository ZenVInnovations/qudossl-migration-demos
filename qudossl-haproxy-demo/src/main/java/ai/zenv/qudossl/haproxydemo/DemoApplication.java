package ai.zenv.qudossl.haproxydemo;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;

/**
 * QudoSSL HAProxy Migration Demo — Spring Boot backend.
 *
 * <p>This application speaks plain HTTP on port 8080 only. It never terminates
 * TLS: HAProxy sits in front of it, terminates TLS, and forwards HTTP here. The
 * QudoSSL migration touches HAProxy, not this app.</p>
 */
@SpringBootApplication
public class DemoApplication {
    public static void main(String[] args) {
        SpringApplication.run(DemoApplication.class, args);
    }
}
