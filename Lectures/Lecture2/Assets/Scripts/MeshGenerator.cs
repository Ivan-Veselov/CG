using System;
using System.Collections.Generic;
using Unity.Mathematics;
using UnityEngine;
using UnityEngine.EventSystems;
using Random = UnityEngine.Random;

struct Vertex {
    public float3 pos;
    public float3 norm;
}

struct Triangle {
    public Vertex v1, v2, v3;
}

[RequireComponent(typeof(MeshFilter))]
public class MeshGenerator : MonoBehaviour
{
    private MeshFilter _filter;
    private Mesh _mesh;

    private const int numOfNoiseVolumes = 4;
    private const int noiseVolumeSize = 16;
    
    private const int blockSize = 32;
        
    private const int voxelsX = blockSize * 7;
    private const int voxelsY = blockSize * 7;
    private const int voxelsZ = blockSize * 7;

    private const int threadsInDimension = 8;
    
    private const int densityBufferSizeX = voxelsX + threadsInDimension;
    private const int densityBufferSizeY = voxelsY + threadsInDimension;
    private const int densityBufferSizeZ = voxelsZ + threadsInDimension;
    
    ComputeShader verticesGeneratorShader;
    
    ComputeBuffer densityFunction;

    private Triangle[] computedTriangles;

    /// <summary>
    /// Executed by Unity upon object initialization. <see cref="https://docs.unity3d.com/Manual/ExecutionOrder.html"/>
    /// </summary>
    private void Awake()
    {
        _filter = GetComponent<MeshFilter>();
        _mesh = _filter.mesh = new Mesh();
        _mesh.MarkDynamic();
        
        runComputeDensity();
        runMarchingCubesKernel();

        densityFunction.Release();
    }

    private void runComputeDensity()
    {
        densityFunction = new ComputeBuffer(
            densityBufferSizeX * densityBufferSizeY * densityBufferSizeZ,
            sizeof(float)
        );

        Texture3D[] randomNoiseVolume = new Texture3D[numOfNoiseVolumes];
        for (int i = 0; i < numOfNoiseVolumes; ++i)
        {
            randomNoiseVolume[i] = new Texture3D(noiseVolumeSize, noiseVolumeSize, noiseVolumeSize, TextureFormat.RFloat, false);
        }

        // only all textures use 0th texture sampler
        randomNoiseVolume[0].filterMode = FilterMode.Trilinear;
        randomNoiseVolume[0].wrapMode = TextureWrapMode.Repeat;

        for (int i = 0; i < numOfNoiseVolumes; ++i)
        {
            for (int x = 0; x < noiseVolumeSize; ++x)
            {
                for (int y = 0; y < noiseVolumeSize; ++y)
                {
                    for (int z = 0; z < noiseVolumeSize; ++z)
                    {
                        randomNoiseVolume[i].SetPixel(x, y, z, new Color(Random.Range(0.0f, 1.0f), 0, 0, 0));
                    }
                }
            }
        }

        verticesGeneratorShader = Resources.Load<ComputeShader>("VerticesGenerator");
        int computeDensityKernel = verticesGeneratorShader.FindKernel("ComputeDensity");
        
        for (int i = 0; i < numOfNoiseVolumes; ++i)
        {
            randomNoiseVolume[i].Apply();
            verticesGeneratorShader.SetTexture(computeDensityKernel, "randomNoiseVolume" + i, randomNoiseVolume[i]);
        }
        
        verticesGeneratorShader.SetBuffer(computeDensityKernel, "densityFunction", densityFunction);
        
        verticesGeneratorShader.Dispatch(
            computeDensityKernel, 
            densityBufferSizeX / threadsInDimension,
            densityBufferSizeY / threadsInDimension,
            densityBufferSizeZ / threadsInDimension
        );
    }
    
    private void runMarchingCubesKernel()
    {
        int marchingCubesKernel = verticesGeneratorShader.FindKernel("MarchingCubes");
        verticesGeneratorShader.SetBuffer(marchingCubesKernel, "densityFunction", densityFunction);

        int[] caseToTrianglesCountInts = new int[MarchingCubes.Tables.CaseToTrianglesCount.Length * 4];
        for (int i = 0; i < MarchingCubes.Tables.CaseToTrianglesCount.Length; ++i)
        {
            caseToTrianglesCountInts[i * 4] = MarchingCubes.Tables.CaseToTrianglesCount[i];
        }
        
        verticesGeneratorShader.SetInts("caseToTrianglesCount", caseToTrianglesCountInts);

        const int maxNumberOfTriangsInVoxel = 5;
        
        var caseToVerticesInts = new int[MarchingCubes.Tables.CaseToVertices.Length * maxNumberOfTriangsInVoxel * 4];
        var ctr = 0;
        for (int i = 0; i < MarchingCubes.Tables.CaseToVertices.Length; ++i)
        {
            for (int j = 0; j < maxNumberOfTriangsInVoxel; ++j)
            {
                int3 value = MarchingCubes.Tables.CaseToVertices[i][j];
                caseToVerticesInts[ctr++] = value.x;
                caseToVerticesInts[ctr++] = value.y;
                caseToVerticesInts[ctr++] = value.z;
                caseToVerticesInts[ctr++] = 0;
            }
        }
        
        verticesGeneratorShader.SetInts("caseToVertices", caseToVerticesInts);

        int[] edgeIndexToVertices = {
            0, 1, 0, 0,
            1, 2, 0, 0,
            3, 2, 0, 0,
            0, 3, 0, 0,
            4, 5, 0, 0,
            5, 6, 0, 0,
            7, 6, 0, 0,
            4, 7, 0, 0,
            0, 4, 0, 0,
            1, 5, 0, 0,
            2, 6, 0, 0,
            3, 7, 0, 0
        };

        verticesGeneratorShader.SetInts("edgeIndexToVertices", edgeIndexToVertices);
        
        ComputeBuffer trianglesBuffer = new ComputeBuffer(
            maxNumberOfTriangsInVoxel * voxelsX * voxelsY * voxelsZ,
            sizeof(float) * 6 * 3,
            ComputeBufferType.Append
        );
        
        trianglesBuffer.SetCounterValue(0);
        
        verticesGeneratorShader.SetBuffer(marchingCubesKernel, "triangles", trianglesBuffer);
        
        verticesGeneratorShader.Dispatch(
            marchingCubesKernel, 
            voxelsX / threadsInDimension,
            voxelsY / threadsInDimension,
            voxelsZ / threadsInDimension
        );
        
        computedTriangles = new Triangle[GetBufferCount(trianglesBuffer)];
        trianglesBuffer.GetData(computedTriangles);
        
        trianglesBuffer.Release();
    }

    private static int GetBufferCount(ComputeBuffer buffer)
    {
        var countBuffer = new ComputeBuffer(1, sizeof(int), ComputeBufferType.IndirectArguments);
        ComputeBuffer.CopyCount(buffer, countBuffer, 0);
        var counter = new[] { 0 };
        countBuffer.GetData(counter);

        return counter[0];
    }

    private void Start()
    {
        List<Vector3> vertices = new List<Vector3>();
        List<Vector3> normals = new List<Vector3>();
        List<int> triangles = new List<int>();

        for (int i = 0; i < computedTriangles.Length; ++i)
        {
            triangles.Add(vertices.Count);
            vertices.Add(computedTriangles[i].v1.pos);
            
            triangles.Add(vertices.Count);
            vertices.Add(computedTriangles[i].v2.pos);
            
            triangles.Add(vertices.Count);
            vertices.Add(computedTriangles[i].v3.pos);
            
            normals.Add(computedTriangles[i].v1.norm);
            normals.Add(computedTriangles[i].v2.norm);
            normals.Add(computedTriangles[i].v3.norm);
        }

        _mesh.indexFormat = UnityEngine.Rendering.IndexFormat.UInt32;
        _mesh.SetVertices(vertices);
        _mesh.SetTriangles(triangles, 0);
        _mesh.SetNormals(normals);
        
        // Upload mesh data to the GPU
        _mesh.UploadMeshData(false);
    }
    
    /// <summary>
    /// Executed by Unity on every first frame <see cref="https://docs.unity3d.com/Manual/ExecutionOrder.html"/>
    /// </summary>
    private void Update()
    {
        
    }
}