//
//  SensorDensity.cpp
//  SensorCloud
//
//  Created by Darko on 2018/4/10.
//  Copyright © 2018年 Darko. All rights reserved.
//

#include "SensorDensity.hpp"
#include<fstream>

using namespace std;

//int* sensor = new int[800];

void densityReader()
{
//    FILE *fpSrc;
//    fpSrc = fopen("density.xyz", "rb");
//    if (fpSrc == NULL) {
//        return;
//    }

    ifstream inf;
    inf.open("density.xyz", ifstream::in);
    
    const int count = 800;
    string line;
    
    int i = 0;
    size_t comma = 0;
    
//    int *sensor = new int[800];
    int k = 0;
    
    while (!inf.eof())
    {
        getline(inf, line);
        
        comma = line.find(',',0);
        i = atoi(line.substr(0,comma).c_str());
        
//        *(SENSOR+k) = i;
        k++;
    }
    
    inf.close();
    
}
