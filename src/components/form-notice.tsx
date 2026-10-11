export function FormNotice({ error, success }: { error?: string; success?: string }) {
  if (error) return <p className="form-notice error" role="alert">{error}</p>;
  if (success) return <p className="form-notice success" role="status">{success}</p>;
  return null;
}
