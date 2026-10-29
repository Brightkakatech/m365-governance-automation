@{
    # Fail the build on errors and warnings.
    Severity     = @('Error', 'Warning')

    # PSUseSingularNouns: PowerShell recommends singular command names
    # (Get-User, not Get-Users). These are report functions whose whole
    # purpose is to return a list, so plural names describe them better.
    # This is a deliberate, documented exception.
    ExcludeRules = @('PSUseSingularNouns')
}
