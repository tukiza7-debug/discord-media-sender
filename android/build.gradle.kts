import com.android.build.api.dsl.LibraryExtension

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
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)

    // Paksa semua modul plugin Android ke compileSdk 36.
    // Sesetengah plugin lama masih menetapkan compileSdk rendah (31/34)
    // dan gagal semasa CheckAarMetadata apabila kebergantungan AndroidX
    // baharu memerlukan SDK lebih tinggi.
    afterEvaluate {
        extensions.findByType(LibraryExtension::class.java)?.let { lib ->
            val current = lib.compileSdk
            if (current == null || current < 36) {
                lib.compileSdk = 36
            }
        }
    }
}

subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
