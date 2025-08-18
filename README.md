# People (Multi-Module Java/Spring Boot Project)

Last updated: 2025-08-18 16:27

## Overview
People is a multi-module Gradle project showcasing a simple People API. The application exposes basic CRUD operations over a People entity via a Spring Boot web API. A small console demo class is also included.

### Modules
- app: Spring Boot application entry point and configuration; also contains a simple console demo class.
- controller: REST controller for People endpoints.
- service: Service layer with business logic.
- repository: In-memory repository for People entities (ConcurrentHashMap-based).
- model: JPA-annotated People entity.

## Requirements
- Java 17 (project uses a Java toolchain set to 17 via build-logic)
- Gradle Wrapper (included). Use ./gradlew on Unix/macOS or gradlew.bat on Windows.

## Build
- Full build (all modules):
  - Unix/macOS: ./gradlew build
  - Windows: gradlew.bat build

- Run unit tests only:
  - ./gradlew test

## Run the Web API (Spring Boot)
The web API entry point is br.com.eichler.people.app.PeopleApplication. The People repository is in-memory, but the app module includes datasource properties for PostgreSQL in app/src/main/resources/application.properties. If you do not have PostgreSQL available, see Option B below to start without a datasource.

- Option A: Start normally (expects PostgreSQL configured in application.properties)
  - ./gradlew :app:bootRun
  - By default, the server runs on http://localhost:8080

- Option B: Start without a datasource (skip JDBC auto-configuration)
  - ./gradlew :app:bootRun --args='--spring.autoconfigure.exclude=org.springframework.boot.autoconfigure.jdbc.DataSourceAutoConfiguration'

- Run as a jar (after build)
  - Build the bootable jar: ./gradlew :app:bootJar
  - Run (with optional exclusion to skip JDBC):
    - java -jar app/build/libs/app-<version>.jar --spring.autoconfigure.exclude=org.springframework.boot.autoconfigure.jdbc.DataSourceAutoConfiguration

Note: The repository is in-memory; no database is required to exercise the API. The JDBC properties are present but not needed unless you later integrate a real database.

## REST API Endpoints
Base path: /people

- Create
  - POST /people?name=John&age=30
  - Response: created People JSON

- Get by ID
  - GET /people/{id}
  - Response: People JSON or empty (HTTP 200 with empty body if not found via Optional)

- List all
  - GET /people
  - Response: JSON array of People

- Update
  - PUT /people/{id}?name=John&age=31
  - Response: updated People JSON or empty if not found

- Delete
  - DELETE /people/{id}
  - Response: boolean (true if deleted)

- Count
  - GET /people/count
  - Response: number of People stored

Example curl commands (assuming Option B run to avoid DB):
- Create: curl -X POST "http://localhost:8080/people?name=Alice&age=25"
- List: curl "http://localhost:8080/people"
- Get: curl "http://localhost:8080/people/1"
- Update: curl -X PUT "http://localhost:8080/people/1?name=Alice&age=26"
- Delete: curl -X DELETE "http://localhost:8080/people/1"
- Count: curl "http://localhost:8080/people/count"

## Console Demo (optional)
A simple console demo exists in the app module (class br.com.eichler.people.app.App) that normalizes whitespace and prints a capitalized message using Apache Commons Text. You can run this class directly from your IDE. The recommended approach for the web API is to use the Spring Boot tasks (:app:bootRun) described above.

## Project Structure (abridged)
- app/
  - src/main/java/br/com/eichler/people/app/PeopleApplication.java
  - src/main/java/br/com/eichler/people/app/App.java
  - src/main/resources/application.properties
- controller/src/main/java/org/example/controller/PeopleController.java
- service/src/main/java/org/example/service/PeopleService.java
- repository/src/main/java/org/example/repository/PeopleRepository.java
- model/src/main/java/org/example/model/People.java

## Notes
- Java toolchain is set to 17 in build-logic (buildlogic.java-common-conventions.gradle).
- Spring Boot version: 3.3.3 (configured in app/build.gradle).
- The REST API scans org.example packages for components. The PeopleApplication class is located in br.com.eichler.people.app and explicitly configures scanBasePackages = "org.example".
- If you introduce a real database, remove the auto-configuration exclusion used in Option B and ensure your datasource is reachable.
- See scripts/README.md for host/VM setup and server provisioning.

## License
Add your license information here.
