for _, id in ipairs({ 17049, 47026 }) do
  local sobj = alife():object( id )
  if sobj then
    log3( "dsh: found %s", sobj:name() )
  else
    log3( "dsh: %s not found", id )
  end
end
