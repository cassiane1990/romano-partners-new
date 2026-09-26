revoke execute on function public.employee_finish_maintenance_service(uuid) from public, anon;
grant execute on function public.employee_finish_maintenance_service(uuid) to authenticated;

revoke execute on function public.maintenance_employee_cleaning_context() from public, anon;
grant execute on function public.maintenance_employee_cleaning_context() to authenticated;
