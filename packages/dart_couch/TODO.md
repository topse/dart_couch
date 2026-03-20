TODO: IndexDocument is nearly a DesignDocument. Check if we can remove IndexDocument and extend DesignDocument.

TODO: HttpDartCouchDb and LocalDartCouchDb currently are mixing in UseDartCouchMixin -- but
      it does not fully work because the changes stream is not automatically restored
      when going offline and back online.
      Maybe it would be the best, only to include the mixin in OfflineFirstDb?
      Or bring the logic of the changes stream to the UseDartCouchMixin?
      Or add tests that stream from HttpDartCouchDb throw an error and shutdown correctly?

TODO: migration: when migration is interrupted by network problems, we should store this state somehow.
      Maybe before starting the migration, set a migration_in_progress flag in the migration
      documents on server and local? So the OfflineFirstDb could go to state "tooOld" to signal, its not ready
      to be used, even when the application restarts (it will find the migratin_in_progress flag!)
      Same on the server: When someone connects and finds the flag, he can finish the migration.
      When not the client reconnects, which also has the flag set, we will check the servers
      document and see, that someone in the meantime has corrected the migration and our flag will
      disappear when the document gets replicated. Then we also can set out state to matched.
      At least it would be good to know, if an initial migration has taken place? Or is in progress?
      Or lock migration for other clients by setting a lock flag in migration document?

TODO: When a app instance tries to create a database that has a tombstone: that is no problem. Just delete
      the Tombstone and create a new database with a new marker document. As the new Marker document
      has new uuids, other instances should be able to sync correctly.

TODO: remove Future.delay
