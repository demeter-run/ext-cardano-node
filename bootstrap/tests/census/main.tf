// Test helper: a textual census of the bootstrap tree (the working directory
// `terraform test` runs in). Every match of every
// pattern in every Terraform, JSON, YAML or template file is reported as
// "<file>:<capture groups>", so a test can pin the exact set. Each pattern
// needs at least one capture group.

variable "patterns" {
  type = list(string)
}

locals {
  files = sort([
    for f in fileset(path.cwd, "**") : f
    if !startswith(f, ".terraform/") && !startswith(f, "tests/") && can(regex("\\.(tf|tf\\.json|json|ya?ml|tftpl|tpl)$", f))
  ])
}

output "matches" {
  value = flatten([
    for f in local.files : [
      for p in var.patterns : [
        for m in regexall(p, file("${path.cwd}/${f}")) : "${f}:${join(" ", m)}"
      ]
    ]
  ])
}
