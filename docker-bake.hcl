variable "PLATFORMS" { default = ["linux/amd64", "linux/arm64"] }
variable "REVISION" { default = "local" }
variable "REPOSITORY_URL" { default = "local" }
variable "IMAGE" { default = "git:local" }

group "default" {
  targets = ["image", "deb", "sources", "repository-test"]
}

target "common" {
  context = "."
  dockerfile = "git.Dockerfile"
  platforms = PLATFORMS
  args = {
    REVISION = REVISION
    REPOSITORY_URL = REPOSITORY_URL
  }
}

target "image" {
  inherits = ["common"]
  target = "artifact"
  tags = [IMAGE]
  output = ["type=oci,dest=dist/git.oci.tar"]
}

target "deb" {
  inherits = ["common"]
  target = "deb"
  output = ["type=local,dest=dist/deb,platform-split=true"]
}

target "sources" {
  inherits = ["common"]
  target = "sources"
  output = ["type=local,dest=dist/sources,platform-split=true"]
}

target "test" {
  inherits = ["common"]
  target = "test"
  output = ["type=local,dest=dist/test,platform-split=true"]
}

target "repository-test" {
  inherits = ["common"]
  target = "repository-test"
  output = ["type=local,dest=dist/repository-test,platform-split=true"]
}

target "source-test" {
  inherits = ["common"]
  target = "source-test"
  output = ["type=local,dest=dist/source-test,platform-split=true"]
}
