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
}
subprojects {
    project.evaluationDependsOn(":app")
}

// Samakan JVM target Kotlin dengan Java (17) di SEMUA plugin.
// Sebagian plugin (mis. file_picker) memakai default Kotlin jvmTarget 21
// sementara Java-nya tetap 17 → Gradle menolak dengan "Inconsistent JVM-target
// compatibility". Menyetelnya terpusat di sini lebih tahan banting daripada
// menambal tiap plugin satu per satu tiap kali versinya naik.
subprojects {
    tasks.withType<org.jetbrains.kotlin.gradle.tasks.KotlinCompile>().configureEach {
        compilerOptions {
            jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
