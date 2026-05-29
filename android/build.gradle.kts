buildscript {
    dependencies {
        classpath("org.jetbrains.kotlin:kotlin-gradle-plugin:2.2.20")
    }
}
plugins {
    id("com.android.application") version "8.11.1" apply false
    id("org.jetbrains.kotlin.plugin.compose") version "2.2.20" apply false
}
allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    // AGP 8.11 computes relative paths for some generated test config files.
    // Keep external Flutter plugins on their native drive to avoid
    // cross-drive relative path failures on Windows.
    if (project.projectDir.toPath().root == newBuildDir.asFile.toPath().root) {
        val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
        project.layout.buildDirectory.value(newSubprojectBuildDir)
    }
}
subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
