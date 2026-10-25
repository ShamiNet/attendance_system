
val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
subprojects {
    project.evaluationDependsOn(":app")
}

subprojects {
    if (name == "geofence_service") {
        val fixGeofence = Action<Project> {
            extensions.configure<com.android.build.api.dsl.LibraryExtension> {
                namespace = "com.pravera.geofence_service"
                compileSdk = 36
            }
        }
        if (state.executed) fixGeofence.execute(this) else afterEvaluate(fixGeofence)
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
