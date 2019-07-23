workflow "Validate" {
  resolves = [
    "ianwremmel/prevent-fixup-commits@v1.0.0",
    "actions/bin/shellcheck@master"
  ]

  on = "push"
}

action "ianwremmel/prevent-fixup-commits@v1.0.0" {
  uses = "ianwremmel/prevent-fixup-commits@v1.0.0"
  secrets = ["GITHUB_TOKEN"]
}

action "actions/bin/shellcheck@master" {
  uses = "actions/bin/shellcheck@master"
}
