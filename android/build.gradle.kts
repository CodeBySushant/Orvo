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
    beforeEvaluate {
        val android = project.extensions.findByName("android") ?: return@beforeEvaluate
        val getNamespace = android.javaClass.methods.firstOrNull { it.name == "getNamespace" }
        val setNamespace = android.javaClass.methods.firstOrNull { it.name == "setNamespace" }
        if (getNamespace != null && setNamespace != null && getNamespace.invoke(android) == null) {
            setNamespace.invoke(android, "com.orvo.${project.name.replace("-", "_")}")
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
