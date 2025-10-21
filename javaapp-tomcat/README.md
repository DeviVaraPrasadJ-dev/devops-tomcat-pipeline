# ArtisanTek Java Tomcat WAR

A beautiful and extremely lightweight Java 21 web application packaged as a `.war` file for deployment on servlet containers like Apache Tomcat.

## Features

- ✨ Beautiful gradient background with animations
- 🎨 Modern glassmorphism design
- 🚀 **Extremely Lightweight**: Built with Javalin for minimal memory usage.
- 📦 Packaged as a standard `.war` file.

## Prerequisites

- Java 21 JDK
- Maven 3.6+
- An Apache Tomcat server (or another Jakarta Servlet container)

## Build Instructions

```bash
# Navigate to the project directory
cd jenkins/java-tomcat-21

# Clean and build the project to create a WAR file
mvn clean package

# The WAR file will be created in the target directory
# File name: artisantek-app.war
```

## Deployment Instructions

1.  **Build the project** using the command above.
2.  **Copy the `target/artisantek-app.war`** file to the `webapps` directory of your Apache Tomcat installation.
3.  **Start Tomcat**. It will automatically detect and deploy the application.
4.  **Access the application** in your browser. If Tomcat is running on port 8080, the URL will be:
    ```
    http://localhost:8080/artisantek-app/
    ```

Enjoy your beautiful and lightweight ArtisanTek web application! 🎉 