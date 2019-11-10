using System;
using Unity.Mathematics;
using UnityEngine;

//[ExecuteInEditMode]
public class CubemapToSphericalHarmonic : MonoBehaviour
{
    private const int SIZE = 1024;
    private int _kernel;

    public float L0;
    public float3 L1;
    public float4 L2_1;
    public float L2_2;
    
    public bool UseCompute;
    
    public Texture2D Env;

    public ComputeShader Compute;
    
    private BufferSetup[] _setups;

    private void SetGrey(string name, Vector4 val)
    {
        Shader.SetGlobalVector(name + "_r", val);
        Shader.SetGlobalVector(name + "_g", val);
        Shader.SetGlobalVector(name + "_b", val);
    }

    void Awake()
    {
        _setups = new []{
            new BufferSetup("SH_0_1_r"), 
            new BufferSetup("SH_0_1_g"), 
            new BufferSetup("SH_0_1_b"), 
        
            new BufferSetup("SH_2_r"), 
            new BufferSetup("SH_2_g"), 
            new BufferSetup("SH_2_b"), 
        
            new BufferSetup("SH_2_rgb")
        };
        
        _kernel = Compute.FindKernel("ComputeHarmonics");
        foreach (var bufferSetup in _setups)
        {
            bufferSetup.Bind(Compute, _kernel);
        }
        Compute.SetTexture(_kernel, "_Env", Env);
    }
    
    void Update()
    {
        if (UseCompute)
        {
            // We don't really have to recalculate SH every frame. It's just here to show you how performant it is.
            Compute.Dispatch(_kernel, 1024, 1, 1);

            foreach (var bufferSetup in _setups)
            {
                bufferSetup.Push();
            }
        }
        else
        {
            SetGrey("SH_0_1", new Vector4(L1.x, L1.y, L1.z, L0));
            SetGrey("SH_2", L2_1);
            Shader.SetGlobalVector("SH_2_rgb", new Vector4(L2_2, L2_2, L2_2));
        }
    }

    private void OnDestroy()
    {
        foreach (var setup in _setups)
        {
            setup.Dispose();
        }
    }
    
    private class BufferSetup: IDisposable
    {
        private readonly ComputeBuffer _buffer;
        private readonly float4[] _destination;
        private string _name;

        public unsafe BufferSetup(string name)
        {
            _name = name;
            
            _buffer = new ComputeBuffer(SIZE, sizeof(float4));
            
            _destination = new float4[SIZE];
        }
        
        public void Push()
        {
            _buffer.GetData(_destination);
            
            float4 sum = 0;
            for (int i = 0; i < SIZE; i++)
            {
                sum += _destination[i];
            }
            
            Shader.SetGlobalVector(_name, sum / SIZE);
        }
        
        public void Bind(ComputeShader computeShader, int kernel)
        {
            computeShader.SetBuffer(kernel, _name, _buffer);
        }
        
        public void Dispose()
        {
            _buffer?.Dispose();
        }
    }
}
