package in.syncgate.api;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.boot.context.properties.ConfigurationPropertiesScan;
import org.springframework.scheduling.annotation.EnableScheduling;

/** SyncGate Phase 1 back end. See docs/backend/README.md. */
@SpringBootApplication
@ConfigurationPropertiesScan
@EnableScheduling
public class SyncgateApiApplication {

    public static void main(String[] args) {
        SpringApplication.run(SyncgateApiApplication.class, args);
    }
}
