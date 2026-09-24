import { withSupabase } from "npm:@supabase/server"

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
}

const COMPANY_TABLES = [
  "companies","profiles","clients","properties","services","service_events","invoices",
  "audit_logs","service_catalog","service_items","employee_profiles","stock_items",
  "laundry_orders","chat_messages","notifications","documents","service_costs","payments",
  "service_media","quality_checklists","employee_documents","recurring_services",
  "work_journal_entries","employee_locations","service_dispatch_attempts","material_requests",
  "occurrences","chat_threads","service_financials","offline_mutations"
]

async function readCompanyTable(admin:any, table:string, companyId:string) {
  const pageSize = 2000
  const rows:any[] = []
  for (let from=0; from<10000; from+=pageSize) {
    const { data, error } = await admin.from(table).select("*").eq("company_id", companyId).range(from, from + pageSize - 1)
    if (error) throw new Error(table + ": " + error.message)
    rows.push(...(data || []))
    if (!data || data.length < pageSize) break
  }
  return rows
}

export default {
  fetch: withSupabase({ auth: "user" }, async (req:any, ctx:any) => {
    if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders })
    const uid = ctx.userClaims?.sub
    if (!uid) return new Response(JSON.stringify({ error: "No autenticado" }), { status: 401, headers: { ...corsHeaders, "Content-Type": "application/json" } })

    const { data: profile, error: profileError } = await ctx.supabase.from("profiles").select("id,company_id,role").eq("id", uid).single()
    if (profileError || !profile || profile.role !== "admin") {
      return new Response(JSON.stringify({ error: "Solo administración puede generar backups." }), { status: 403, headers: { ...corsHeaders, "Content-Type": "application/json" } })
    }

    const admin = ctx.supabaseAdmin
    const exportId = crypto.randomUUID()
    const startedAt = new Date().toISOString()
    const rowCounts:any = {}
    const snapshot:any = {
      format: "ROMANO_PARTNERS_LOGICAL_BACKUP_V1",
      export_id: exportId,
      company_id: profile.company_id,
      created_by: uid,
      created_at: startedAt,
      source: "Supabase PostgreSQL + Storage metadata",
      tables: {}
    }

    try {
      for (const table of COMPANY_TABLES) {
        const rows = await readCompanyTable(admin, table, profile.company_id)
        snapshot.tables[table] = rows
        rowCounts[table] = rows.length
      }

      const threadIds = (snapshot.tables.chat_threads || []).map((x:any) => x.id).filter(Boolean)
      if (threadIds.length) {
        const { data: members, error } = await admin.from("chat_members").select("*").in("thread_id", threadIds)
        if (error) throw new Error("chat_members: " + error.message)
        snapshot.tables.chat_members = members || []
        rowCounts.chat_members = (members || []).length
      } else {
        snapshot.tables.chat_members = []
        rowCounts.chat_members = 0
      }

      snapshot.storage_metadata = {}
      for (const bucket of ["service-media","company-documents"]) {
        const { data: objects, error } = await admin.schema("storage").from("objects").select("bucket_id,name,size,mime_type,created_at,updated_at").eq("bucket_id", bucket).limit(10000)
        if (!error) snapshot.storage_metadata[bucket] = objects || []
      }

      const body = JSON.stringify(snapshot)
      const path = profile.company_id + "/" + new Date().toISOString().slice(0,10) + "/romano-backup-" + exportId + ".json"
      const upload = await admin.storage.from("romano-backups").upload(path, new Blob([body], { type: "application/json" }), { contentType: "application/json", cacheControl: "3600", upsert: false })
      if (upload.error) throw new Error("Storage: " + upload.error.message)

      const { data: signed, error: signError } = await admin.storage.from("romano-backups").createSignedUrl(path, 3600)
      if (signError) throw new Error("Signed URL: " + signError.message)

      const bytes = new TextEncoder().encode(body).byteLength
      const { error: logError } = await admin.from("backup_exports").insert({
        id: exportId, company_id: profile.company_id, created_by: uid, storage_path: path,
        status: "completed", row_counts: rowCounts, bytes, completed_at: new Date().toISOString()
      })
      if (logError) throw new Error("Registro backup: " + logError.message)

      return new Response(JSON.stringify({ ok:true, export_id:exportId, path, bytes, row_counts:rowCounts, signed_url:signed?.signedUrl||null }), {
        headers: { ...corsHeaders, "Content-Type": "application/json" }
      })
    } catch (error:any) {
      await admin.from("backup_exports").insert({
        id: exportId, company_id: profile.company_id, created_by: uid, storage_path: "failed/" + exportId,
        status: "failed", row_counts: rowCounts, error_message: String(error?.message || error).slice(0,1000)
      })
      return new Response(JSON.stringify({ ok:false, export_id:exportId, error:String(error?.message || error) }), {
        status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" }
      })
    }
  })
}