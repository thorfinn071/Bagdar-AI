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

subprojects {
    fun configureProject(p: Project) {
        val android = p.extensions.findByName("android")
        if (android != null) {
            try {
                val getNamespace = android.javaClass.getMethod("getNamespace")
                val namespace = getNamespace.invoke(android) as? String
                if (namespace.isNullOrEmpty()) {
                    val manifestFile = p.file("src/main/AndroidManifest.xml")
                    if (manifestFile.exists()) {
                        val manifestContent = manifestFile.readText()
                        val packageMatch = Regex("package=\"([^\"]+)\"").find(manifestContent)
                        if (packageMatch != null) {
                            val setNamespace = android.javaClass.getMethod("setNamespace", String::class.java)
                            setNamespace.invoke(android, packageMatch.groupValues[1])
                            p.logger.quiet("Dynamically set namespace for subproject ${p.name} to ${packageMatch.groupValues[1]}")
                        }
                    }
                }
            } catch (e: Exception) {
                // Ignore if method or class does not exist
            }
        }
    }

    if (state.executed) {
        configureProject(this)
    } else {
        afterEvaluate {
            configureProject(this)
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}

