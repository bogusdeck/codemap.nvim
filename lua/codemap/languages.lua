local M = {}

M.all = {
  { label = "Go", filetype = "go", ext = "go" },
  { label = "Python", filetype = "python", ext = "py" },
  { label = "JavaScript", filetype = "javascript", ext = "js" },
  { label = "TypeScript", filetype = "typescript", ext = "ts" },
  { label = "Java", filetype = "java", ext = "java" },
  { label = "C++", filetype = "cpp", ext = "cpp" },
  { label = "C", filetype = "c", ext = "c" },
  { label = "Rust", filetype = "rust", ext = "rs" },
  { label = "Ruby", filetype = "ruby", ext = "rb" },
}

function M.find_by_filetype(filetype)
  for _, language in ipairs(M.all) do
    if language.filetype == filetype then
      return language
    end
  end

  return nil
end

function M.find_by_name(name)
  if not name then
    return nil
  end

  for _, language in ipairs(M.all) do
    if language.filetype == name or language.ext == name or language.label:lower() == name:lower() then
      return language
    end
  end

  return nil
end

function M.default_for(filetype)
  return M.find_by_name(filetype) or M.all[1]
end

return M
