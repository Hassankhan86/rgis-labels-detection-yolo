import com.android.build.gradle.LibraryExtension

allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

// The `onnxruntime` plugin's own android/build.gradle hardcodes
// compileSdkVersion 33, which no longer satisfies several AndroidX
// libraries pulled in transitively by other plugins (e.g. camera's
// CameraX backend), and fails `:onnxruntime:checkDebugAarMetadata`.
// Force every Android-library plugin subproject to compile against the
// same SDK as the app itself, overriding whatever each plugin declares.
subprojects {
    afterEvaluate {
        extensions.findByType(LibraryExtension::class.java)?.let { android ->
            android.compileSdk = 36
        }
    }
}

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

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
