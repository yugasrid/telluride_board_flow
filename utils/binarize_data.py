import argparse
import os
import numpy as np

'''
python binarize_data.py --data_path ../pso2_2560/layer1_21/data
'''

def txt2bin(txtPath: str, binPath:str):
    txt_data = np.loadtxt(txtPath, dtype='uint32', converters={_: lambda s: int(s, 16) for _ in range(1)})
    txt_data = txt_data.view('uint16').astype('uint16')
    data_size = (int)(txt_data.size * 2)

    data_size = np.array([data_size,0]).astype(np.uint32).view(np.uint16)
    txt_data = np.append(data_size, txt_data)

    txt_data.tofile(binPath)

if __name__ == "__main__":
    parser = argparse.ArgumentParser(usage=None)
    parser.add_argument('--data_path', type=str, default='../pso2_2560/layer1_21/data')
    args = parser.parse_args()
    data_path = args.data_path
    dirs = os.listdir(data_path)
    txt_name = ['ifm32.txt', 'wts32.txt', 'ofm32_ref.txt']
    for _ in txt_name:
        if _ in dirs:
            txtPath = os.path.join(data_path, _)
            binPath = txtPath.replace('.txt', '.bin')
            txt2bin(txtPath, binPath)
