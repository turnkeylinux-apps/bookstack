BookStack - Simple & Free Wiki Software
=======================================

BookStack_ is a simple, self-hosted, easy-to-use platform for organising and
storing information. It includes a simple WYSIWYG interface or optional
markdown editor with live-preview. BookStack is built using PHP (Laravel
framework), backed by a MySQL/MariaDB database. The content is fully searchable
and includes cross-linking ability, page revisions and image management.

BookStack includes all the standard features in `TurnKey Core`_, and on
top of that:

- SSL support out of the box.
- `Adminer`_ administration frontend for MySQL (MariaDB) (listening on port
  12322 - uses SSL).
- `Postfix`_ MTA (bound to localhost) to allow sending of email.
- Webmin modules for configuring Apache2, PHP, MySQL and Postfix.

Credentials *(passwords set at first boot)*
-------------------------------------------

- Webmin, SSH, MySQL: username **root**

- Adminer: username **adminer**

- BookStack: username is email - set at firstboot

.. _BookStack: https://www.bookstackapp.com/
.. _TurnKey Core: https://www.turnkeylinux.org/core
.. _Adminer: https://www.adminer.org/
.. _Postfix: https://www.postfix.org/
