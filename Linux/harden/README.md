Post initial scripts for hardening

1. rbash.sh - Jail 4 u
    ```
    Example: -E 'REVERT=blabla'

    @ PARAMS
    REVERT -    If defined, restores the backed up /etc/password. Optional.
                This is in case rbashing things screwed stuff up.
    ```