==================================================================
kw-patch-track - Track and display patches sent with kw-send-patch
==================================================================

.. _patch-track-doc:

SYNOPSIS
========
| *kw patch-track* [OPTIONS]

DESCRIPTION
===========
The `kw patch-track` feature manages local tracking of patch submissions sent via 
`kw send-patch`. It works by scraping metadata from submission logs to populate 
a local database, keeping record of shipping dates, status, and titles. 

Beyond simple visualization, it provides a heuristic engine to automatically 
update patch statuses based on mailing list activity and allows for deep 
integration with the `mutt` email client to facilitate review follow-ups.

OPTIONS
=======
--show-patches:
  Displays the patches dashboard in chronological order, showing patch ID, 
  creation date, current status, and title.

-d, --show-contributions:
  Displays the contributions dashboard, grouping sets of patches into higher-level 
  contribution entities.

-f <YYYY-MM-DD>, --from <YYYY-MM-DD>, -a <YYYY-MM-DD>, --after <YYYY-MM-DD>:
  Filters the dashboard to display only patches created on or after the specified date.

-b <YYYY-MM-DD>, --before <YYYY-MM-DD>:
  Filters the dashboard to display only patches created before the specified date.

--id <patch_id>:
  Specifies a unique patch ID for status modification.

-s <status>, --set-status <status>:
  Manually sets a new status for a specific patch (specified via --id). 
  Available statuses: SUBMITTED, REVIEWED, APPROVED, MERGED, REJECTED.

-u, --update:
  Triggers the automated heuristic engine to update patch statuses by analyzing 
  associated email threads.

-c <contribution_id>, --contribution-id <contribution_id>:
  Specifies the contribution ID to be used with repository or mutt operations.

--set-repository <name:url>:
  Associates a repository name and its origin URL to a contribution. 
  Requires --contribution-id.

-r <repository_id>, --repository-id <repository_id>:
  Specifies the repository ID to be used with maintainer operations.

-m <name:email>, --set-maintainer <name:email>:
  Associates a maintainer's name and email to a specific repository. 
  Requires --repository-id.

-o, --open-contribution:
  Opens the email thread associated with a contribution directly in the `mutt` 
  terminal client. Requires --contribution-id.

EXAMPLES
========
To view the chronological dashboard of all patches:

  kw patch-track --show-patches

To view grouped contributions:

  kw patch-track --show-contributions

To filter patches submitted within a specific timeframe:

  kw patch-track --show-patches --after 2023-01-01 --before 2023-12-31

To manually update a patch status after a maintainer's feedback:

  kw patch-track --id 42 --set-status APPROVED

To run the automatic status update heuristics:

  kw patch-track --update

To link a contribution to a specific subsystem repository:

  kw patch-track --contribution-id 10 --set-repository "linux-usb:https://git.kernel.org/..."

To open a specific contribution thread in mutt for review:

  kw patch-track --contribution-id 10 --open-contribution