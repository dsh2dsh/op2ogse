local obj = db.actor:object( "wpn_ak12" )
if obj then
  log3( "dsh: found %s", obj:name() )
  db.actor:move_to_slot( obj )
end
