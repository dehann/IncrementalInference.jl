# Factor Graph OS type utilities
#  IIF methods should direclty detect extended types from user import
# of convert in their namespace


function convert{PT <: PackedInferenceType, T <:FunctorInferenceType}(::Type{PT}, ::T)
  getfield(T.name.module, Symbol("Packed$(T.name.name)"))
end
function convert{T <: FunctorInferenceType, PT <: PackedInferenceType}(::Type{T}, ::PT)
  getfield(PT.name.module, Symbol(string(PT.name.name)[7:end]))
end



"""
    convert2packedfunctionnode(fgl::FactorGraph, fsym::Symbol)

Encode complicated function node type with assumed to exist, user supplied convert
fucntion to related 'Packed<type>' format.
"""
function convert2packedfunctionnode(fgl::FactorGraph,
      fsym::Symbol,
      api::DataLayerAPI=localapi  )
  #
  fid = fgl.fIDs[fsym]
  fnc = getfnctype(fgl, fid)
  usrtyp = convert(PackedInferenceType, fnc)
  cfnd = convert(PackedFunctionNodeData{usrtyp},getData(fgl, fid, api=api) )
  return cfnd, usrtyp
end




"""
    encodefg(fgl::FactorGraph)

Make a full memory copy of the graph and encode all complicated function node
types with assumed to exist convert to 'Packed<type>' formats. Same converters
as used for database persistence storage with CloudGraphs.jl.
"""
function encodefg(fgl::FactorGraph;
      api::DataLayerAPI=localapi  )
  #
  fgs = deepcopy(fgl)
  fgs.cg = nothing
  fgs.registeredModuleFunctions = nothing
  fgs.g = Graphs.incdict(Graphs.ExVertex,is_directed=false)
  @showprogress 1 "Encoding variables..." for (vsym,vid) in fgl.IDs
    cpvert = deepcopy(getVert(fgl, vid, api=api))
    api.addvertex!(fgs, cpvert) #, labels=vnlbls)  # currently losing labels
  end

  @showprogress 1 "Encoding factors..." for (fsym,fid) in fgs.fIDs
    data,ftyp = convert2packedfunctionnode(fgl, fsym)
    # data = FunctionNodeData{ftyp}(Int64[], false, false, Int64[], m, gwpf)
    newvert = ExVertex(fid,string(fsym))
    for (key,val) in getVert(fgl,fid,api=api).attributes
      newvert.attributes[key] = val
    end
    setData!(newvert, data)
    api.addvertex!(fgs, newvert)
  end
  fgs.g.inclist = typeof(fgl.g.inclist)()

  # iterated over all edges
  @showprogress 1 "Encoding edges..." for (eid, edges) in fgl.g.inclist
    fgs.g.inclist[eid] = Vector{typeof(edges[1])}()
    for ed in edges
      newed = Graphs.Edge(ed.index,
          fgs.g.vertices[ed.source.index],
          fgs.g.vertices[ed.target.index]  )
      push!(fgs.g.inclist[eid], newed)
    end
  end

  return fgs
end

"""
    savefgjld(fgl::FactorGraph; file::AbstractString="tempfg.jld")

Save mostly complete Factor Graph type by converting complicated FunctionNodeData
types to 'Packed' types using user supplied converters. Ground truth can also be
saved and recovered by the associated loadjld(file="tempfg.jld") method.
"""
function savejld(fgl::FactorGraph;
      file::AbstractString="tempfg.jld",
      groundtruth=nothing)
  fgs = encodefg(fgl)
  if groundtruth == nothing
    @save file fgs
  else
    @save file fgs groundtruth
  end
  return file
end


"""
    convertfrompackedfunctionnode(fgl, fsym)

If you get unknown type conversion error when loading a .jld, while using your own
FunctorInferenceTypes, you should:
Copy these functions below, and overload in your package with local extented
FunctorInferenceType definitions.
See RoME/src/fgos.jl for example.
"""
function convertfrompackedfunctionnode(fgl::FactorGraph,
      fsym::Symbol,
      api::DataLayerAPI=localapi  )
  #
  fid = fgl.fIDs[fsym]
  fnc = getData(fgl, fid).fnc #getfnctype(fgl, fid)
  usrtyp = convert(FunctorInferenceType, fnc)
  data = getData(fgl, fid, api=api)
  newtype = FunctionNodeData{GenericWrapParam{usrtyp}}
  cfnd = convert(newtype, data)
  return cfnd, usrtyp
end

"""
    decodefg(fgs::FactorGraph)

Unpack PackedFunctionNodeData formats back to regular FunctonNodeData.
"""
function decodefg(fgs::FactorGraph; api::DataLayerAPI=localapi)
  fgu = deepcopy(fgs)
  fgu.cg = nothing
  fgu.registeredModuleFunctions = nothing
  fgu.g = Graphs.incdict(Graphs.ExVertex,is_directed=false)
  @showprogress 1 "Decoding variables..." for (vsym,vid) in fgs.IDs
    cpvert = deepcopy(getVert(fgs, vid, api=api))
    api.addvertex!(fgu, cpvert) #, labels=vnlbls)  # currently losing labels
  end

  @showprogress 1 "Decoding factors..." for (fsym,fid) in fgu.fIDs
    data,ftyp = convertfrompackedfunctionnode(fgs, fsym)
    # data = FunctionNodeData{ftyp}(Int64[], false, false, Int64[], m, gwpf)
    newvert = ExVertex(fid,string(fsym))
    for (key,val) in getVert(fgs,fid,api=api).attributes
      newvert.attributes[key] = val
    end
    setData!(newvert, data)
    api.addvertex!(fgu, newvert)
  end
  fgu.g.inclist = typeof(fgs.g.inclist)()

  # iterated over all edges
  @showprogress 1 "Decoding edges..." for (eid, edges) in fgs.g.inclist
    fgu.g.inclist[eid] = Vector{typeof(edges[1])}()
    for ed in edges
      newed = Graphs.Edge(ed.index,
          fgu.g.vertices[ed.source.index],
          fgu.g.vertices[ed.target.index]  )
      push!(fgu.g.inclist[eid], newed)
    end
  end

  return fgu
end

"""
    loadjld(file="tempfg.jld")

Opposite of savejld(fg, gt=gt, file="tempfg.jl") to load data from file. This function
uses the unpacking converters for converting all PackedInferenceType to FunctorInferenceType.
"""
function loadjld(;file::AbstractString="tempfg.jld")
  dd = JLD.load(file)
  # fgs = jldopen(file,"r") do file
  #   read(file, "fgs")
  # end
  fgs, gt = nothing, nothing
  if haskey(dd, "fgs")
    fgs = dd["fgs"]
  else
    error("No factor graph (fgs) data found in this file, only found $(keys(dd))")
  end
  if haskey(dd, "groundtruth")
    gt = dd["groundtruth"]
    println("Also found ground truth data")
  end
  fgd = decodefg(fgs)
  return fgd, gt
end








#