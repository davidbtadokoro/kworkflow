==================================================================
kw-patch-track - Track and display patches sent with kw-send-patch
==================================================================

.. _patch-track-doc:

SYNOPSIS
========
| *kw patch-track*

DESCRIPTION
===========
The `kw patch-track` feature deal with tracking the patches submissions using the
feature `kw send-patch`, keeping notes of it's shipping date, status, title,
making it possible to view shipments, and update their status as needed.

OPTIONS
=======
-d, \--dashboard:
  Displays the patches dashboard, showing the patches id, created date-time,
  status and title.

-a <YYYY-MM-DD>, \--after <YYYY-MM-DD>:
  Specify a date to look up for the patches after this date.

-b <YYYY-MM-DD>', \--before <YYYY-MM-DD>:
  Specify a date to look up for the patches before this date.

-f <YYYY-MM-DD>, \--from <YYYY-MM-DD>:
  Specify a date to look up for the patches from this date.

\--id '<id>'
  Specify a patch id 

--s='<status>', \--set-status='<status>'
  Set a new status for an specific patch as SENT, APPROVED,
  REJECTED, MERGED or REVIEWED.

EXAMPLES
========
To check your patches dashboard use:

  kw patch-track --dashboard

For checking your patches within an specific date use: 

  kw patch-track --dashboard --from <YYYY-MM-DD>

To check your patches after an specific date:

  kw patch-track --dashboard --after <YYYY-MM-DD>

And to check the patches before an specific date, use:

  kw patch-track --dashboard --before <YYYY-MM-DD>

To change the patch status for an specific patch

  kw patch-track --id <id> --set-status <status>