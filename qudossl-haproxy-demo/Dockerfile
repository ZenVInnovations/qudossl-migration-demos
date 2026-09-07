# QudoSSL HAProxy Migration Demo — Spring Boot backend image.
# Multi-stage: build the jar with Maven, run it on a slim JRE as a non-root user.
# This container speaks plain HTTP on 8080. It has no TLS and does not change
# during the QudoSSL migration.

# --- build stage ------------------------------------------------------------
FROM maven:3.9-eclipse-temurin-17 AS build
WORKDIR /src
COPY pom.xml .
RUN mvn -q -e -B dependency:go-offline
COPY src ./src
RUN mvn -q -e -B clean package -DskipTests

# --- runtime stage ----------------------------------------------------------
FROM eclipse-temurin:17-jre-jammy
WORKDIR /app
# Run as a non-root user.
RUN useradd -r -u 1001 -m appuser
COPY --from=build /src/target/qudossl-haproxy-demo.jar /app/app.jar
USER appuser
EXPOSE 8080

# Health check hits the backend's own /health endpoint.
HEALTHCHECK --interval=10s --timeout=3s --start-period=30s --retries=5 \
  CMD ["sh", "-c", "wget -qO- http://127.0.0.1:8080/health | grep -q UP || exit 1"]

ENTRYPOINT ["java", "-jar", "/app/app.jar"]
